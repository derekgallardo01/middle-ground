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
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
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
        guard let uid = Auth.auth().currentUser?.uid else { return }
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
        let token: String?
        if let fcmToken {
            token = fcmToken
        } else {
            token = try? await Messaging.messaging().token()
        }
        guard let token else { return }
        await Self.persist(token: token)
    }

    /// Detach this device on sign-out so it stops receiving the previous account's pushes.
    func removeTokenForCurrentUser() async {
        guard let uid = Auth.auth().currentUser?.uid, let fcmToken else { return }
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
        guard let requestID = userInfo["request_id"] as? String else { return }
        // Post a notification that AppState/Coordinator can observe to navigate
        NotificationCenter.default.post(
            name: .didReceiveRequestNotification,
            object: nil,
            userInfo: ["request_id": requestID]
        )
    }
}

extension Notification.Name {
    static let didReceiveRequestNotification = Notification.Name("didReceiveRequestNotification")
}
