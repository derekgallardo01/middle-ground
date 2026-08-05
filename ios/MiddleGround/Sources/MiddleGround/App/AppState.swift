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

    /// An invite code from a link somebody tapped, waiting for a screen that can use it.
    ///
    /// It arrives before we know who this is or whether they have finished onboarding, so it is
    /// parked here rather than pushed at a view. Onboarding takes it if the person is new;
    /// Profile takes it if they are not. Cleared once used, so it cannot be redeemed twice.
    ///
    /// This is the whole point of the universal link: without it the code can only travel as
    /// prose in a message, and the recipient has to notice it, copy it, and retype it after an
    /// App Store detour.
    var pendingInviteCode: String?

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

        // The splash clears on the *synchronous* answer to "is anyone signed in?", which comes
        // straight off the in-memory session. It used to wait for `currentUser()` — a Firestore
        // read of the user document — so on a cold or slow network that round trip was the
        // entire perceived launch time, spent learning something the app already knew.
        //
        // The document still loads, just behind the first frame: the display name it carries is
        // not needed to decide which screen to show.
        isOnboarded = authService.currentUserID != nil
        isCheckingAuth = false

        await LoadTimer.measure("startup.user") {
            currentUser = await authService.currentUser()
        }
        // Corrects the optimistic answer in the one case it can be wrong: a session that still
        // exists on the device but whose account has since been deleted server-side.
        isOnboarded = currentUser != nil
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
