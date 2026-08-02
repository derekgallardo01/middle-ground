import UIKit
import FirebaseAppCheck
import FirebaseCore
import FirebaseCrashlytics
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

        // App Check must be installed BEFORE configure() — the provider factory is read
        // during configuration, and setting it afterwards silently has no effect.
        AppCheck.setAppCheckProviderFactory(MGAppCheckProviderFactory())

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
}

/// Chooses an App Check attestation provider.
///
/// App Attest is hardware-backed and only exists on a real device; the simulator has no
/// attestation key, so a debug provider is used there. The debug token it prints has to be
/// registered in the Firebase console before it is accepted.
///
/// IMPORTANT: enforcement is currently OFF in the Firebase console, so an unattested request
/// is still served. Turning it on before App Attest has been proven on physical hardware
/// would lock every real client out of Firestore with no way to recover from the client side.
/// Verify via TestFlight on a device first, then enable enforcement.
final class MGAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if targetEnvironment(simulator)
        return AppCheckDebugProvider(app: app)
        #else
        // App Attest needs iOS 14+; the deployment target is 17.
        return AppAttestProvider(app: app)
        #endif
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
