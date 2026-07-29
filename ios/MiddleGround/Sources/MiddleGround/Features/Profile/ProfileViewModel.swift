import Foundation
import Factory

@MainActor
@Observable
final class ProfileViewModel {
    private let authService = Container.shared.authService()
    private let gamificationService = Container.shared.gamificationService()
    private let notificationService = NotificationService.shared
    
    var user: User?
    var stats: GamificationStats?
    var notificationsEnabled = false
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
            await checkNotificationStatus()
        }
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
    
    func toggleNotifications() async {
        if notificationsEnabled {
            // Can't programmatically disable; direct to Settings
        } else {
            _ = await notificationService.requestAuthorization()
            await checkNotificationStatus()
        }
    }
    
    func signOut() async -> Bool {
        isLoading = true
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
