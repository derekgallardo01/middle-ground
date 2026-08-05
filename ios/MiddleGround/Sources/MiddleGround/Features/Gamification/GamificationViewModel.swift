import Foundation
import Factory

@MainActor
@Observable
final class GamificationViewModel {
    private let gamificationService = Container.shared.gamificationService()
    private let authService = Container.shared.authService()
    private let requestService = Container.shared.requestService()
    private let relationshipRepository = Container.shared.relationshipRepository()
    private let userRepository = Container.shared.userRepository()

    /// Derived from the request history rather than stored, so it can never drift from the
    /// records it is drawn from — and there is no separate number to tamper with.
    private(set) var reliability: ReliabilityScore?

    /// One board per eligible group — never for a couple, never for two people. See
    /// `GroupScoreboard` for why that rule is in the type rather than in this screen.
    private(set) var scoreboards: [(group: Relationship, board: GroupScoreboard)] = []

    /// How often each group's plans happen. Every group, couples included — it ranks nobody.
    private(set) var followThrough: [(group: Relationship, rate: GroupFollowThrough)] = []

    /// Every group, so the screen can tell "nothing earned yet" from "nobody to earn it with".
    private(set) var groups: [Relationship] = []

    /// The code to show when there is nobody to plan with, or nil when it would be ambiguous —
    /// the same rule Home and Calendar use.
    var soleInviteCode: String? {
        let unpaired = groups.filter { !$0.isPaired }
        return unpaired.count == 1 ? unpaired.first?.inviteCode : nil
    }

    var currentUser: User?
    var stats: GamificationStats = GamificationStats(streakDays: 0, relationshipXP: 0, level: 1, growthScore: 0, nextLevelXP: 500)
    var achievements: [Achievement] = []
    var activities: [Activity] = []
    var weeklyCompletion: [Bool] = Array(repeating: false, count: 7)

    var isLoading = false

    /// False until the first load finishes.
    ///
    /// `isLoading` is false *before* the first load starts, so the opening frame drew the
    /// real screen from default values — Level 1, 0 XP, a 0-day streak and the "how this
    /// works" primer — and then rewrote itself once the real numbers arrived. Worse than a
    /// flash: for a moment it told an established user they had no progress.
    private(set) var hasLoaded = false
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
            await loadScoreboards(from: requests)
        }
        isLoading = false
        hasLoaded = true
    }

    /// Builds a board for each group that may have one.
    ///
    /// Names are fetched only for members of eligible groups, so a couple costs no reads at all.
    private func loadScoreboards(from requests: [Request]) async {
        guard let currentUser else { return }
        let allGroups = (try? await relationshipRepository.fetchRelationships(for: currentUser.id)) ?? []
        groups = allGroups

        // Follow-through covers every group; the scoreboard does not. One fetch answers both.
        followThrough = allGroups.map { group in
            (group, GroupFollowThrough.from(relationship: group, requests: requests))
        }

        let groups = allGroups.filter(GroupScoreboard.isEligible)
        guard !groups.isEmpty else {
            scoreboards = []
            return
        }

        var names: [String: String] = [currentUser.id: currentUser.name]
        for userID in Set(groups.flatMap(\.participantIDs)) where names[userID] == nil {
            if let user = try? await userRepository.user(id: userID) {
                names[userID] = user.name
            }
        }

        scoreboards = groups.compactMap { group in
            guard let board = GroupScoreboard.from(
                relationship: group, requests: requests, names: names
            ), board.isWorthShowing else { return nil }
            return (group, board)
        }
    }
}
