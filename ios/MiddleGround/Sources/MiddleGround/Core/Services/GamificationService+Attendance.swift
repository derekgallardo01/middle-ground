import Foundation

/// Paying out a plan once its outcome is known.
///
/// Split out for the same reason as the mock: the service was at the 500-line limit, and
/// settlement is a separate concern from the response reward loop — it is triggered by a plan
/// reaching a state rather than by anybody doing anything.
extension GamificationService {
    /// Pays out a settled plan: XP for having turned up, plus whatever the stake came to.
    ///
    /// Deliberately idempotent. Settlement is one event shared by several people, but each device
    /// can only write its own user's progress — and the person who confirmed first has already
    /// closed the app by the time the last answer lands. So this is called both when a
    /// confirmation completes the set and whenever a settled plan is opened, and `settledPlanIDs`
    /// is what makes the second and third call cost nothing.
    @discardableResult
    func recordAttendance(of request: Request, for userID: String) async -> GamificationOutcome? {
        // Same reasoning as `recordResponse`: read after restoring, or the first write after a
        // reinstall replaces real history with a default.
        await restoreFromMirrorIfNeeded(for: userID)

        guard request.allParticipantIDs.contains(userID) else { return nil }
        guard request.everyoneHasAnswered else { return nil }

        var stats = await stats(for: userID)
        guard !stats.settledPlanIDs.contains(request.id) else { return nil }

        let attended = request.isConfirmedComplete
        // A plan that fell through costs nothing on its own. Only a stake takes XP away, because
        // that is the one case where the user chose to put something at risk.
        let attendanceXP = attended ? GamificationRules.attendedXP : 0
        let stakeDelta = request.stakeOutcome(for: userID)
        let total = attendanceXP + stakeDelta

        // Floored at zero. A losing stake can cost you the points you have and no more — going
        // negative would mean a level below 1 and a progress bar reading backwards.
        stats.relationshipXP = max(0, stats.relationshipXP + total)
        stats.level = GamificationRules.level(forXP: stats.relationshipXP)
        stats.nextLevelXP = GamificationRules.nextLevelXP(forXP: stats.relationshipXP)

        if request.category != .unknown {
            let current = stats.categoryXP[request.category.rawValue] ?? 0
            stats.categoryXP[request.category.rawValue] = max(0, current + total)
        }

        if attended { stats.attendedCount += 1 }

        stats.settledPlanIDs.append(request.id)
        // Bounded: the ledger only has to outlive the window in which a plan can still be
        // settled, which is days, not the lifetime of the account.
        if stats.settledPlanIDs.count > 500 {
            stats.settledPlanIDs.removeFirst(stats.settledPlanIDs.count - 500)
        }

        await save(stats: stats, for: userID)

        let newlyUnlocked = await unlockAchievements(with: stats, for: userID)
        if total != 0 {
            await appendActivities(
                FeedEntry(
                    xpAwarded: total,
                    subtitle: Self.settlementDescription(attended: attended, stake: stakeDelta),
                    stats: stats,
                    streakExtended: false,
                    newlyUnlocked: newlyUnlocked
                ),
                for: userID
            )
        }

        return GamificationOutcome(
            stats: stats,
            xpAwarded: total,
            newlyUnlocked: newlyUnlocked,
            streakExtended: false
        )
    }

    private static func settlementDescription(attended: Bool, stake: Int) -> String {
        switch (attended, stake) {
        case (true, let stake) where stake > 0: return "You turned up, and won your stake back"
        case (true, _): return "You turned up"
        case (false, let stake) where stake < 0: return "The plan fell through, and cost you your stake"
        case (false, _): return "The plan didn't happen"
        }
    }
}
