import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

public final class AppDelegate: NSObject, UIApplicationDelegate {
    override public init() { super.init() }

    let notificationService = NotificationService.shared

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        Task { _ = await notificationService.requestAuthorization() }
        return true
    }

    public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    public func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        MGLog.notifications.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }
}
