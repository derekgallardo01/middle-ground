import Foundation
import Factory

@MainActor
@Observable
final class GamificationViewModel {
    private let gamificationService = Container.shared.gamificationService()
    private let authService = Container.shared.authService()
    private let requestService = Container.shared.requestService()

    /// Derived from the request history rather than stored, so it can never drift from the
    /// records it is drawn from — and there is no separate number to tamper with.
    private(set) var reliability: ReliabilityScore?

    var currentUser: User?
    var stats: GamificationStats = GamificationStats(streakDays: 0, relationshipXP: 0, level: 1, growthScore: 0, nextLevelXP: 500)
    var achievements: [Achievement] = []
    var activities: [Activity] = []
    var weeklyCompletion: [Bool] = Array(repeating: false, count: 7)

    var isLoading = false
    var errorMessage: String?

    var progressToNextLevel: Double {
        guard stats.nextLevelXP > 0 else { return 0 }
        return min(Double(stats.relationshipXP) / Double(stats.nextLevelXP), 1.0)
    }

    var unlockedAchievements: [Achievement] {
        achievements.filter(\.isUnlocked)
    }

    var lockedAchievements: [Achievement] {
        achievements.filter { !$0.isUnlocked }
    }

    func loadCurrentUser() async {
        currentUser = await authService.currentUser()
    }

    func loadGamificationData() async {
        guard let currentUser else {
            errorMessage = "Not signed in."
            return
        }
        isLoading = true
        errorMessage = nil
        // Before the reads, not alongside them: on a reinstall the local store is empty, and
        // the mirror is the only place the user's XP and streak still exist.
        await gamificationService.restoreFromMirrorIfNeeded(for: currentUser.id)
        async let fetchedStats = gamificationService.stats(for: currentUser.id)
        async let fetchedAchievements = gamificationService.achievements(for: currentUser.id)
        async let fetchedActivities = gamificationService.activities(for: currentUser.id)
        async let fetchedWeek = gamificationService.weeklyCompletion(for: currentUser.id)
        let (stats, achievements, activities, week) = await (fetchedStats, fetchedAchievements, fetchedActivities, fetchedWeek)
        self.stats = stats
        self.achievements = achievements
        self.activities = activities
        self.weeklyCompletion = week

        // Best-effort: a failed request fetch costs the reliability card, not the whole screen.
        if let requests = try? await requestService.fetchRequests(for: currentUser.id) {
            reliability = ReliabilityScore.from(requests: requests, userID: currentUser.id)
        }
        isLoading = false
    }
}
