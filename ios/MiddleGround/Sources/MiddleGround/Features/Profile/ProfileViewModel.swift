import Foundation
import UIKit
import Factory

@MainActor
@Observable
final class ProfileViewModel {
    private let authService = Container.shared.authService()
    private let gamificationService = Container.shared.gamificationService()
    private let notificationService = NotificationService.shared
    private let relationshipService = Container.shared.relationshipService()

    var user: User?
    var stats: GamificationStats?
    var notificationsEnabled = false
    var relationships: [Relationship] = []

    /// The code this user shares to invite a partner, if they own an unpaired relationship.
    var inviteCode: String? {
        relationships.first { !$0.isPaired }?.inviteCode ?? relationships.first?.inviteCode
    }

    var isPaired: Bool { relationships.contains(where: \.isPaired) }
    var isLoading = false
    var errorMessage: String?

    var levelDisplay: String {
        guard let stats else { return "" }
        return "Level \(stats.level) · \(stats.relationshipXP.formatted()) XP"
    }

    init() {
        Task {
            await loadUser()
            await loadStats()
            await loadRelationships()
            await checkNotificationStatus()
        }
    }

    func loadRelationships() async {
        guard let user else { return }
        relationships = (try? await relationshipService.relationships(for: user.id)) ?? []
    }

    func loadUser() async {
        user = await authService.currentUser()
    }

    func loadStats() async {
        guard let user else { return }
        stats = await gamificationService.stats(for: user.id)
    }

    func checkNotificationStatus() async {
        await notificationService.checkAuthorizationStatus()
        notificationsEnabled = notificationService.hasPermission
    }

    /// iOS has no API to revoke notification permission, so turning it off opens Settings.
    func toggleNotifications() async {
        if notificationsEnabled {
            openSystemSettings()
        } else {
            _ = await notificationService.requestAuthorization()
            await checkNotificationStatus()
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func signOut() async -> Bool {
        isLoading = true
        await NotificationService.shared.removeTokenForCurrentUser()
        do {
            try await authService.signOut()
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
}
