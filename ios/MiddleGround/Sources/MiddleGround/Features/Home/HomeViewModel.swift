import Foundation
import Factory

@MainActor
@Observable
final class HomeViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    private let gamificationService = Container.shared.gamificationService()

    var requests: [Request] = []
    var currentUser: User?
    var stats: GamificationStats = GamificationStats(streakDays: 0, relationshipXP: 0, level: 1, growthScore: 0, nextLevelXP: 500)
    var isLoading = false
    var errorMessage: String?
    var showCelebration = false
    var celebrationTitle = ""

    init() {
        Task {
            await loadCurrentUser()
            await loadRequests()
            await loadStats()
        }
    }

    func loadCurrentUser() async {
        currentUser = await authService.currentUser()
    }

    func loadStats() async {
        guard let currentUser else { return }
        stats = await gamificationService.stats(for: currentUser.id)
    }

    func loadRequests() async {
        guard let currentUser else {
            errorMessage = "Not signed in."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            requests = try await requestService.fetchRequests(for: currentUser.id)
        } catch {
            errorMessage = "Couldn't load requests. Pull to try again."
        }
        isLoading = false
    }

    /// Streams live updates. Runs for the lifetime of the view via `.task`.
    func observeRequests() async {
        if currentUser == nil { await loadCurrentUser() }
        guard let currentUser else { return }
        for await updated in requestService.observeRequests(for: currentUser.id) {
            requests = updated
            isLoading = false
        }
    }

    func respond(to request: Request, with response: ResponseType) {
        guard let currentUser else { return }
        Task {
            do {
                let updated = try await requestService.respond(to: request, with: response, by: currentUser.id)
                if let index = requests.firstIndex(where: { $0.id == updated.id }) {
                    requests[index] = updated
                }

                // Award XP / streak / achievements, then reflect the new totals immediately.
                let outcome = await gamificationService.recordResponse(response, to: request, for: currentUser.id)
                stats = outcome.stats
                celebrate(response: response, outcome: outcome)
            } catch {
                errorMessage = "Failed to send response."
            }
        }
    }

    private func celebrate(response: ResponseType, outcome: GamificationOutcome) {
        if let unlocked = outcome.newlyUnlocked.first {
            triggerCelebration("Achievement unlocked: \(unlocked.title)")
        } else if response == .accept {
            triggerCelebration("Request accepted! +\(outcome.xpAwarded) XP")
        } else if response == .negotiate {
            triggerCelebration("Let's find a middle ground")
        }
    }

    private func triggerCelebration(_ title: String) {
        celebrationTitle = title
        showCelebration = true
        Haptics.shared.notification(.success)
    }
}
