import Foundation

/// Preview and UI-test double for `GamificationServiceProtocol`.
///
/// Lives in its own file rather than alongside the real service: the two together pushed
/// GamificationService.swift past the 500-line limit, and a fully-populated fake has nothing
/// to do with the UserDefaults-backed implementation anyway.
actor MockGamificationService: GamificationServiceProtocol {
    /// No-op: the mock's stats are already fully populated, so there is nothing to restore.
    func restoreFromMirrorIfNeeded(for userID: String) async {}

    func stats(for userID: String) async -> GamificationStats {
        GamificationStats(
            streakDays: 12,
            relationshipXP: 2450,
            level: 8,
            growthScore: 85,
            nextLevelXP: 3000,
            acceptedCount: 14,
            negotiatedCount: 11,
            weekendAcceptedCount: 5,
            lastResponseDate: Date()
        )
    }

    @discardableResult
    func recordResponse(_ response: ResponseType, to request: Request, for userID: String) async -> GamificationOutcome {
        GamificationOutcome(
            stats: await stats(for: userID),
            xpAwarded: GamificationRules.xp(for: response),
            newlyUnlocked: [],
            streakExtended: false
        )
    }

    /// Always pays, so previews and UI tests can show a settlement without staging one.
    @discardableResult
    func recordAttendance(of request: Request, for userID: String) async -> GamificationOutcome? {
        GamificationOutcome(
            stats: await stats(for: userID),
            xpAwarded: GamificationRules.attendedXP + request.stakeOutcome(for: userID),
            newlyUnlocked: [],
            streakExtended: false
        )
    }

    func weeklyCompletion(for userID: String) async -> [Bool] {
        [true, true, true, true, false, true, true]
    }

    func achievements(for userID: String) async -> [Achievement] {
        [
            Achievement(
                id: "ach_1",
                title: "Great Communicator",
                description: "Resolved 10 requests through compromise",
                iconName: "trophy.fill",
                requiredValue: 10,
                unlockedAt: Date()
            ),
            Achievement(
                id: "ach_2",
                title: "Weekend Warrior",
                description: "Planned 5 weekend activities together",
                iconName: "airplane",
                requiredValue: 5,
                unlockedAt: Date()
            ),
            Achievement(
                id: "ach_3",
                title: "Streak Starter",
                description: "Complete a request 3 days in a row",
                iconName: "flame.fill",
                requiredValue: 3,
                unlockedAt: Date()
            ),
            Achievement(
                id: "ach_4",
                title: "Master Compromiser",
                description: "Resolve 50 requests through negotiation",
                iconName: "handshake.fill",
                requiredValue: 50,
                unlockedAt: nil
            )
        ]
    }

    func activities(for userID: String) async -> [Activity] {
        [
            Activity(
                userID: userID,
                type: .streakUpdate,
                title: "12 day streak",
                subtitle: "Keep it going!",
                value: 12
            ),
            Activity(
                userID: userID,
                type: .xpEarned,
                title: "+25 XP",
                subtitle: "Accepted a request",
                value: 25
            ),
            Activity(
                userID: userID,
                type: .achievementUnlocked,
                title: "Great Communicator",
                subtitle: "Achievement unlocked",
                value: 1
            ),
            Activity(
                userID: userID,
                type: .milestoneReached,
                title: "10 requests resolved",
                subtitle: "Healthy communication milestone",
                value: 10
            )
        ]
    }
}
