import Foundation
import Factory

@MainActor
@Observable
final class AppState {
    private let authService = Container.shared.authService()
    private let analytics = Container.shared.analyticsService()

    var isOnboarded = false
    var currentUser: User?
    var selectedTab: Tab = .home
    var isCheckingAuth = true

    /// Mirrors the server-issued `admin` claim. Drives whether the Admin tab is rendered;
    /// the real enforcement is in `firestore.rules`.
    var isAdmin = false

    /// A request a push notification asked us to open, held until the feed can resolve it.
    ///
    /// Needed because a cold launch from a push delivers the notification long before
    /// `loadRequests()` finishes, so looking the id up immediately finds nothing and the tap
    /// is silently dropped. Buffering it lets Home open the request as soon as it arrives.
    var pendingRequestID: String?

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
        Task {
            await analytics.track(.onboardingCompleted, userID: user.id)
            await NotificationService.shared.syncTokenForCurrentUser()
        }
    }

    /// Records that the app came to the foreground.
    ///
    /// Debounced: `scenePhase` flips to `.active` on every return from the app switcher,
    /// Control Centre, or a notification banner, so an undebounced event would fire dozens of
    /// times an hour and drown the rest of the log. One per half hour is enough to see whether
    /// someone is actually using the app.
    private var lastAppOpenTrackedAt: Date?

    func trackAppOpened() async {
        guard let userID = currentUser?.id else { return }
        let now = Date()
        if let last = lastAppOpenTrackedAt, now.timeIntervalSince(last) < 1_800 { return }
        lastAppOpenTrackedAt = now
        await analytics.track(.appOpened, userID: userID)
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
