import Foundation

protocol GamificationServiceProtocol: Sendable {
    func stats(for userID: String) async -> GamificationStats
    func achievements(for userID: String) async -> [Achievement]
    func activities(for userID: String) async -> [Activity]
}

struct GamificationStats: Codable, Equatable {
    var streakDays: Int
    var relationshipXP: Int
    var level: Int
    var growthScore: Int
    var nextLevelXP: Int
}

actor GamificationService: GamificationServiceProtocol {
    private let store = UserDefaults.standard
    
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
            return activities.sorted(by: { $0.timestamp > $1.timestamp })
        }
        return defaultActivities(for: userID)
    }
    
    func save(stats: GamificationStats, for userID: String) async {
        if let data = try? JSONEncoder().encode(stats) {
            store.set(data, forKey: statsKey(for: userID))
        }
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
    
    private func defaultActivities(for userID: String) -> [Activity] {
        [
            Activity(
                userID: userID,
                type: .streakUpdate,
                title: "Started your journey",
                subtitle: "Welcome to Middle Ground",
                value: 1
            )
        ]
    }
}

actor MockGamificationService: GamificationServiceProtocol {
    func stats(for userID: String) async -> GamificationStats {
        GamificationStats(streakDays: 12, relationshipXP: 2450, level: 8, growthScore: 85, nextLevelXP: 3000)
    }
    
    func achievements(for userID: String) async -> [Achievement] {
        [
            Achievement(id: "ach_1", title: "Great Communicator", description: "Resolved 10 requests through compromise", iconName: "trophy.fill", requiredValue: 10, unlockedAt: Date()),
            Achievement(id: "ach_2", title: "Weekend Warrior", description: "Planned 5 weekend activities together", iconName: "airplane", requiredValue: 5, unlockedAt: Date()),
            Achievement(id: "ach_3", title: "Streak Starter", description: "Complete a request 3 days in a row", iconName: "flame.fill", requiredValue: 3, unlockedAt: Date()),
            Achievement(id: "ach_4", title: "Master Compromiser", description: "Resolve 50 requests through negotiation", iconName: "handshake.fill", requiredValue: 50, unlockedAt: nil)
        ]
    }
    
    func activities(for userID: String) async -> [Activity] {
        [
            Activity(userID: userID, type: .streakUpdate, title: "12 day streak", subtitle: "Keep it going!", value: 12),
            Activity(userID: userID, type: .xpEarned, title: "+25 XP", subtitle: "Accepted a request", value: 25),
            Activity(userID: userID, type: .achievementUnlocked, title: "Great Communicator", subtitle: "Achievement unlocked", value: 1),
            Activity(userID: userID, type: .milestoneReached, title: "10 requests resolved", subtitle: "Healthy communication milestone", value: 10)
        ]
    }
}
