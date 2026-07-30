import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

public final class AppDelegate: NSObject, UIApplicationDelegate {
    override public init() { super.init() }

    // NOTE: NotificationService is deliberately *not* a stored property here.
    // Stored properties initialise during `AppDelegate.init`, which runs before
    // `didFinishLaunchingWithOptions` — and `NotificationService.init` used to reach for
    // `Messaging.messaging()`. That put a Firebase call ahead of `FirebaseApp.configure()`,
    // which traps: "The default FirebaseApp instance must be configured before the default
    // Messaging instance can be initialized." The app crashed before its first frame.

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard AppConfiguration.isBackendEnabled else {
            // Mock mode: no Firebase at all, so the app runs with no GoogleService-Info.plist.
            MGLog.storage.info("Launching in mock mode — Firebase is not configured.")
            return true
        }

        FirebaseApp.configure()
        // Only now is it safe to touch anything Firebase-backed.
        NotificationService.shared.start()

        // Deliberately does NOT request notification permission here. Onboarding has a
        // dedicated "Stay in sync" step that explains why first; asking on launch both
        // preempted that step and produced a second, context-free prompt.
        // Re-register for remote notifications only if the user already granted it.
        Task { await NotificationService.shared.registerIfAlreadyAuthorized() }
        return true
    }

    public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard AppConfiguration.isBackendEnabled else { return }
        Messaging.messaging().apnsToken = deviceToken
    }

    public func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        MGLog.notifications.error(
            "Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)"
        )
    }
}
