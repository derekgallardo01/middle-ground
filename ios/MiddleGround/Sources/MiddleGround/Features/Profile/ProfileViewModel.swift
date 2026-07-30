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
    private let signInManager = Container.shared.signInWithAppleManager()

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
    var isDeletingAccount = false
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

    /// Deletes the account for good.
    ///
    /// Apple requires the Sign in with Apple token to be revoked on deletion, and revocation
    /// needs a *fresh* single-use authorization code — so this re-presents the Apple sheet
    /// before deleting. Anonymous test accounts have no Apple credential and skip straight
    /// to deletion.
    func deleteAccount() async -> Bool {
        isDeletingAccount = true
        errorMessage = nil
        defer { isDeletingAccount = false }

        await notificationService.removeTokenForCurrentUser()

        let authorizationCode = await freshAppleAuthorizationCode()
        do {
            try await authService.deleteAccount(appleAuthorizationCode: authorizationCode)
            return true
        } catch {
            errorMessage = "Couldn't delete your account. Please try again."
            return false
        }
    }

    /// Re-runs Sign in with Apple purely to obtain a revocation code. Returns nil if the
    /// user cancels or the account isn't Apple-backed; deletion still proceeds.
    private func freshAppleAuthorizationCode() async -> String? {
        await withCheckedContinuation { continuation in
            signInManager.signIn { result in
                switch result {
                case .success(let apple): continuation.resume(returning: apple.authorizationCode)
                case .failure: continuation.resume(returning: nil)
                }
            }
        }
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
