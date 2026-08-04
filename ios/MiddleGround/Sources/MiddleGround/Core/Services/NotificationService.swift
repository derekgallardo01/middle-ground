import Foundation
import UIKit
import UserNotifications
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore

final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published var fcmToken: String?
    @Published var hasPermission = false

    override private init() {
        super.init()
        // Nothing Firebase-backed here: this singleton can be created before
        // FirebaseApp.configure() runs (or in mock mode, where it never runs).
        UNUserNotificationCenter.current().delegate = self
    }

    /// Attaches the Firebase Messaging delegate. Must be called *after*
    /// `FirebaseApp.configure()`, from `AppDelegate.didFinishLaunchingWithOptions`.
    func start() {
        guard AppConfiguration.isBackendEnabled else { return }
        Messaging.messaging().delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            await MainActor.run {
                self.hasPermission = granted
            }
            if granted {
                await UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            return false
        }
    }

    /// Re-registers for remote notifications on launch when permission was already granted,
    /// without prompting. Prompting is owned by the onboarding permissions step.
    func registerIfAlreadyAuthorized() async {
        guard AppConfiguration.isBackendEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        await MainActor.run { self.hasPermission = true }
        await UIApplication.shared.registerForRemoteNotifications()
    }

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.hasPermission = settings.authorizationStatus == .authorized
        }
    }
}

extension NotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        self.fcmToken = fcmToken
        guard let fcmToken else { return }
        Task { await Self.persist(token: fcmToken) }
    }
}

// MARK: - Device token registration

extension NotificationService {
    private static let tokenCollection = "user_tokens"

    /// Cloud Functions read `user_tokens/{uid}.tokens` to target devices, so a token that is
    /// never written here means push silently never arrives.
    static func persist(token: String) async {
        guard AppConfiguration.isBackendEnabled, let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await Firestore.firestore()
                .collection(tokenCollection)
                .document(uid)
                .setData(["tokens": FieldValue.arrayUnion([token])], merge: true)
        } catch {
            MGLog.notifications.error("Failed to persist FCM token: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The token usually arrives before anyone is signed in, so re-attach it after auth.
    func syncTokenForCurrentUser() async {
        guard AppConfiguration.isBackendEnabled else { return }
        let token: String?
        if let fcmToken {
            token = fcmToken
        } else {
            token = try? await Messaging.messaging().token()
        }
        guard let token else { return }
        await Self.persist(token: token)
    }

    /// Clears the app-icon badge.
    ///
    /// Cloud Functions set the badge to the recipient's real pending count, and nothing in the
    /// app ever reset it — so once a push arrived the icon carried a number indefinitely, even
    /// after every request had been answered. Called when the app becomes active.
    func clearBadge() async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(0)
        } catch {
            MGLog.notifications.error("Could not clear badge: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Detach this device on sign-out so it stops receiving the previous account's pushes.
    func removeTokenForCurrentUser() async {
        guard AppConfiguration.isBackendEnabled,
              let uid = Auth.auth().currentUser?.uid,
              let fcmToken else { return }
        do {
            try await Firestore.firestore()
                .collection(Self.tokenCollection)
                .document(uid)
                .setData(["tokens": FieldValue.arrayRemove([fcmToken])], merge: true)
        } catch {
            MGLog.notifications.error("Failed to remove FCM token: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notification while app is in foreground
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        handleNotification(userInfo: userInfo)
    }

    private func handleNotification(userInfo: [AnyHashable: Any]) {
        if let requestID = userInfo["request_id"] as? String {
            // Post a notification that AppState/Coordinator can observe to navigate
            NotificationCenter.default.post(
                name: .didReceiveRequestNotification,
                object: nil,
                userInfo: ["request_id": requestID]
            )
            return
        }

        // The weekly nudge names a group rather than a plan, because its whole point is that
        // there is no plan. It was the only push that did nothing when tapped: this handler
        // required a `request_id` and returned early, so the app opened on whatever tab you
        // happened to leave it on. There is nothing to open, so it lands on the feed — where
        // making a plan starts.
        if userInfo["relationship_id"] is String {
            NotificationCenter.default.post(name: .didReceiveNudgeNotification, object: nil)
        }
    }
}

extension Notification.Name {
    static let didReceiveRequestNotification = Notification.Name("didReceiveRequestNotification")
    /// A nudge to plan something, which points at the feed rather than at any one plan.
    static let didReceiveNudgeNotification = Notification.Name("didReceiveNudgeNotification")
}
