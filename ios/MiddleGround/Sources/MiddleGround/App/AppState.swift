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

    /// Mirrors the server-issued `admin` claim. Drives whether the Admin tab is rendered;
    /// the real enforcement is in `firestore.rules`.
    var isAdmin = false

    enum Tab {
        case home
        case calendar
        case activities
        case profile
        case admin
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
        MGLog.setCrashReportingUser(currentUser?.id)
        if currentUser != nil {
            isAdmin = await authService.isAdmin()
            await NotificationService.shared.syncTokenForCurrentUser()
        } else {
            isAdmin = false
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
        isAdmin = false
    }
}
