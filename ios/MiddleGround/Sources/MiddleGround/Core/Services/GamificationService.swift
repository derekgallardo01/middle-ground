import Foundation

protocol GamificationServiceProtocol: Sendable {
    func stats(for userID: String) async -> GamificationStats
    func achievements(for userID: String) async -> [Achievement]
    func activities(for userID: String) async -> [Activity]

    /// Pulls progress back from the server when this device has none.
    ///
    /// Call this before the first `stats(for:)` of a session. It was missing from the
    /// protocol, which is why the implementation had no call sites and progress still did not
    /// survive a reinstall despite being mirrored on every save.
    func restoreFromMirrorIfNeeded(for userID: String) async

    /// Awards XP, extends the streak, and unlocks achievements for a response the user just sent.
    /// This is the write path that turns the Activities tab from decoration into a real reward loop.
    @discardableResult
    func recordResponse(_ response: ResponseType, to request: Request, for userID: String) async -> GamificationOutcome

    /// Day-by-day completion flags for the current week, for the streak strip.
    func weeklyCompletion(for userID: String) async -> [Bool]
}

/// What a single response earned, so the UI can celebrate specifics.
struct GamificationOutcome: Equatable, Sendable {
    var stats: GamificationStats
    var xpAwarded: Int
    var newlyUnlocked: [Achievement]
    var streakExtended: Bool
}

struct GamificationStats: Codable, Equatable, Sendable {
    var streakDays: Int
    var relationshipXP: Int
    var level: Int
    var growthScore: Int
    var nextLevelXP: Int

    // Counters backing achievement progress.
    var acceptedCount: Int
    var negotiatedCount: Int
    var weekendAcceptedCount: Int
    var lastResponseDate: Date?

    init(
        streakDays: Int,
        relationshipXP: Int,
        level: Int,
        growthScore: Int,
        nextLevelXP: Int,
        acceptedCount: Int = 0,
        negotiatedCount: Int = 0,
        weekendAcceptedCount: Int = 0,
        lastResponseDate: Date? = nil
    ) {
        self.streakDays = streakDays
        self.relationshipXP = relationshipXP
        self.level = level
        self.growthScore = growthScore
        self.nextLevelXP = nextLevelXP
        self.acceptedCount = acceptedCount
        self.negotiatedCount = negotiatedCount
        self.weekendAcceptedCount = weekendAcceptedCount
        self.lastResponseDate = lastResponseDate
    }

    /// Tolerates blobs written before the counter fields existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streakDays = try container.decodeIfPresent(Int.self, forKey: .streakDays) ?? 0
        relationshipXP = try container.decodeIfPresent(Int.self, forKey: .relationshipXP) ?? 0
        level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 1
        growthScore = try container.decodeIfPresent(Int.self, forKey: .growthScore) ?? 0
        nextLevelXP = try container.decodeIfPresent(Int.self, forKey: .nextLevelXP) ?? GamificationRules.xpPerLevel
        acceptedCount = try container.decodeIfPresent(Int.self, forKey: .acceptedCount) ?? 0
        negotiatedCount = try container.decodeIfPresent(Int.self, forKey: .negotiatedCount) ?? 0
        weekendAcceptedCount = try container.decodeIfPresent(Int.self, forKey: .weekendAcceptedCount) ?? 0
        lastResponseDate = try container.decodeIfPresent(Date.self, forKey: .lastResponseDate)
    }
}

/// Tuning constants for the reward loop, kept in one place.
enum GamificationRules {
    static let xpPerLevel = 500

    static func xp(for response: ResponseType) -> Int {
        switch response {
        case .accept: return 25
        case .negotiate, .counter: return 15
        case .reschedule: return 10
        case .decline, .save: return 5
        }
    }

    static func level(forXP xp: Int) -> Int { max(1, xp / xpPerLevel + 1) }

    static func nextLevelXP(forXP xp: Int) -> Int { level(forXP: xp) * xpPerLevel }

    /// Bounded 0...100 so the Home "Growth Score" card stays meaningful.
    static func growthScore(accepted: Int, negotiated: Int, streakDays: Int) -> Int {
        min(100, accepted * 3 + negotiated * 2 + streakDays)
    }
}

actor GamificationService: GamificationServiceProtocol {
    private let store: UserDefaults
    private let mirror: GamificationRepository?
    /// Users whose mirror has already been consulted this session.
    private var restoreAttempted: Set<String> = []

    /// Pass a dedicated suite in tests so runs don't leak state into each other.
    ///
    /// `mirror` writes progress through to Firestore so it survives a device change — and so it
    /// is measurable at all. Nil in tests, which keeps them offline and deterministic.
    init(store: UserDefaults = .standard, mirror: GamificationRepository? = nil) {
        self.store = store
        self.mirror = mirror
    }

    func stats(for userID: String) async -> GamificationStats {
        if let data = store.data(forKey: statsKey(for: userID)),
           let stats = try? JSONDecoder().decode(GamificationStats.self, from: data) {
            return stats
        }
        return defaultStats
    }

    func achievements(for userID: String) async -> [Achievement] {
        if let data = store.data(forKey: achievementsKey(for: userID)),
           let achievements = try? JSONDecoder().decode([Achievement].self, from: data) {
            return achievements
        }
        return defaultAchievements
    }

    func activities(for userID: String) async -> [Activity] {
        if let data = store.data(forKey: activitiesKey(for: userID)),
           let activities = try? JSONDecoder().decode([Activity].self, from: data) {
            return activities.sorted { $0.timestamp > $1.timestamp }
        }
        // Genuinely empty, rather than a seeded "Started your journey" row.
        //
        // That placeholder was indistinguishable from real logged activity — it rendered in
        // the same list, with the same styling — so a user with no history was shown
        // something that looked like history. It also made the real empty state in
        // ActivityFeedView unreachable, which is why nobody had noticed it was never seen.
        return []
    }

    func save(stats: GamificationStats, for userID: String) async {
        if let data = try? JSONEncoder().encode(stats) {
            store.set(data, forKey: statsKey(for: userID))
        }
        // Local store stays the fast path; the mirror is the durable copy.
        await mirror?.save(stats, for: userID)
    }

    /// Restores progress from the server when the device has none — the case that used to lose
    /// a user's entire history on reinstall or device change.
    ///
    /// Restores the stats only: XP, level, streak and growth score. The mirror does not carry
    /// achievements or the activity feed, so those still start empty on a new device.
    ///
    /// Callers invoke this on every load, so the attempt is recorded per user. Without that,
    /// a user who genuinely has no progress anywhere never populates the local store and would
    /// re-read the mirror on every single load.
    func restoreFromMirrorIfNeeded(for userID: String) async {
        guard !restoreAttempted.contains(userID) else { return }
        restoreAttempted.insert(userID)
        guard store.data(forKey: statsKey(for: userID)) == nil,
              let remote = try? await mirror?.stats(for: userID),
              let data = try? JSONEncoder().encode(remote) else { return }
        store.set(data, forKey: statsKey(for: userID))
    }

    func save(achievements: [Achievement], for userID: String) async {
        if let data = try? JSONEncoder().encode(achievements) {
            store.set(data, forKey: achievementsKey(for: userID))
        }
    }

    func save(activities: [Activity], for userID: String) async {
        if let data = try? JSONEncoder().encode(activities) {
            store.set(data, forKey: activitiesKey(for: userID))
        }
    }

    // MARK: - Write path

    @discardableResult
    func recordResponse(_ response: ResponseType, to request: Request, for userID: String) async -> GamificationOutcome {
        // Restore before reading, or this method destroys progress.
        //
        // It reads local state and then writes the result through to the mirror. After a
        // reinstall the local store is empty, so without this the first response builds on
        // `defaultStats` and that write replaces the user's real history in Firestore —
        // silently, and with nothing to recover from. Restoring here rather than in a view
        // model means no screen can reach this method by a path that skips it, and the
        // per-user `restoreAttempted` guard makes the repeat calls free.
        await restoreFromMirrorIfNeeded(for: userID)

        var stats = await stats(for: userID)
        let calendar = Calendar.current
        let now = Date()

        // Streak: same day is a no-op, the next day extends, any longer gap resets to 1.
        var streakExtended = false
        if let last = stats.lastResponseDate {
            let lastDay = calendar.startOfDay(for: last)
            let today = calendar.startOfDay(for: now)
            let dayGap = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if dayGap == 1 {
                stats.streakDays += 1
                streakExtended = true
            } else if dayGap > 1 {
                stats.streakDays = 1
                streakExtended = true
            }
        } else {
            stats.streakDays = 1
            streakExtended = true
        }
        stats.lastResponseDate = now

        let xpAwarded = GamificationRules.xp(for: response)
        stats.relationshipXP += xpAwarded
        stats.level = GamificationRules.level(forXP: stats.relationshipXP)
        stats.nextLevelXP = GamificationRules.nextLevelXP(forXP: stats.relationshipXP)

        switch response {
        case .accept:
            stats.acceptedCount += 1
            if let proposed = request.proposedTime, calendar.isDateInWeekend(proposed) {
                stats.weekendAcceptedCount += 1
            }
        case .negotiate, .counter:
            stats.negotiatedCount += 1
        case .decline, .reschedule, .save:
            break
        }

        stats.growthScore = GamificationRules.growthScore(
            accepted: stats.acceptedCount,
            negotiated: stats.negotiatedCount,
            streakDays: stats.streakDays
        )

        await save(stats: stats, for: userID)

        let newlyUnlocked = await unlockAchievements(with: stats, for: userID)
        await appendActivities(
            FeedEntry(
                xpAwarded: xpAwarded,
                response: response,
                stats: stats,
                streakExtended: streakExtended,
                newlyUnlocked: newlyUnlocked
            ),
            for: userID
        )

        return GamificationOutcome(
            stats: stats,
            xpAwarded: xpAwarded,
            newlyUnlocked: newlyUnlocked,
            streakExtended: streakExtended
        )
    }

    func weeklyCompletion(for userID: String) async -> [Bool] {
        let calendar = Calendar.current
        // Only XP-earning activity counts as completing a day; the welcome entry does not.
        let activityDays = Set(
            await activities(for: userID)
                .filter { $0.type == .xpEarned }
                .map { calendar.startOfDay(for: $0.timestamp) }
        )

        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return Array(repeating: false, count: 7)
        }

        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return false }
            return activityDays.contains(calendar.startOfDay(for: day))
        }
    }

    /// Marks achievements unlocked once their counter reaches `requiredValue`.
    private func unlockAchievements(with stats: GamificationStats, for userID: String) async -> [Achievement] {
        var achievements = await achievements(for: userID)
        var newlyUnlocked: [Achievement] = []

        for index in achievements.indices where !achievements[index].isUnlocked {
            let progress: Int
            switch achievements[index].id {
            case "ach_1", "ach_4": progress = stats.negotiatedCount
            case "ach_2": progress = stats.weekendAcceptedCount
            case "ach_3": progress = stats.streakDays
            default: progress = 0
            }

            if progress >= achievements[index].requiredValue {
                achievements[index].unlockedAt = Date()
                newlyUnlocked.append(achievements[index])
            }
        }

        if !newlyUnlocked.isEmpty {
            await save(achievements: achievements, for: userID)
        }
        return newlyUnlocked
    }

    private struct FeedEntry {
        let xpAwarded: Int
        let response: ResponseType
        let stats: GamificationStats
        let streakExtended: Bool
        let newlyUnlocked: [Achievement]
    }

    private func appendActivities(_ entry: FeedEntry, for userID: String) async {
        let xpAwarded = entry.xpAwarded
        let response = entry.response
        let stats = entry.stats
        let streakExtended = entry.streakExtended
        let newlyUnlocked = entry.newlyUnlocked

        var activities = await activities(for: userID)

        activities.append(
            Activity(
                userID: userID,
                type: .xpEarned,
                title: "+\(xpAwarded) XP",
                subtitle: response.activityDescription,
                value: xpAwarded
            )
        )

        if streakExtended {
            activities.append(
                Activity(
                    userID: userID,
                    type: .streakUpdate,
                    title: "\(stats.streakDays) day streak",
                    subtitle: stats.streakDays > 1 ? "Keep it going!" : "You're on the board",
                    value: stats.streakDays
                )
            )
        }

        for achievement in newlyUnlocked {
            activities.append(
                Activity(
                    userID: userID,
                    type: .achievementUnlocked,
                    title: achievement.title,
                    subtitle: "Achievement unlocked",
                    value: 1
                )
            )
        }

        // Keep the local feed bounded.
        let trimmed = activities.sorted { $0.timestamp > $1.timestamp }.prefix(50)
        await save(activities: Array(trimmed), for: userID)
    }

    private func statsKey(for userID: String) -> String { "gamification_stats_\(userID)" }
    private func achievementsKey(for userID: String) -> String { "gamification_achievements_\(userID)" }
    private func activitiesKey(for userID: String) -> String { "gamification_activities_\(userID)" }

    private var defaultStats: GamificationStats {
        GamificationStats(streakDays: 0, relationshipXP: 0, level: 1, growthScore: 0, nextLevelXP: 500)
    }

    private var defaultAchievements: [Achievement] {
        [
            Achievement(
                id: "ach_1",
                title: "Great Communicator",
                description: "Resolved 10 requests through compromise",
                iconName: "trophy.fill",
                requiredValue: 10,
                unlockedAt: nil
            ),
            Achievement(
                id: "ach_2",
                title: "Weekend Warrior",
                description: "Planned 5 weekend activities together",
                iconName: "airplane",
                requiredValue: 5,
                unlockedAt: nil
            ),
            Achievement(
                id: "ach_3",
                title: "Streak Starter",
                description: "Complete a request 3 days in a row",
                iconName: "flame.fill",
                requiredValue: 3,
                unlockedAt: nil
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

}
