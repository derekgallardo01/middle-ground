import Foundation
import Factory

@MainActor
@Observable
final class AppState {
    private let authService = Container.shared.authService()

    var isOnboarded = false
    var currentUser: User?
    var selectedTab: Tab = .home
    var isCheckingAuth = true

    enum Tab {
        case home
        case calendar
        case activities
        case profile
    }

    init() {
        Task {
            await checkAuthState()
        }
    }

    func checkAuthState() async {
        isCheckingAuth = true
        currentUser = await authService.currentUser()
        isOnboarded = currentUser != nil
        isCheckingAuth = false
        if currentUser != nil {
            await NotificationService.shared.syncTokenForCurrentUser()
        }
    }

    func completeOnboarding(user: User) {
        currentUser = user
        isOnboarded = true
        Task { await NotificationService.shared.syncTokenForCurrentUser() }
    }

    func signOut() async {
        await NotificationService.shared.removeTokenForCurrentUser()
        try? await authService.signOut()
        // Derived, per-account data must not outlive the session on a shared device.
        LocalStore.shared.purgeAll()
        currentUser = nil
        isOnboarded = false
    }
}
