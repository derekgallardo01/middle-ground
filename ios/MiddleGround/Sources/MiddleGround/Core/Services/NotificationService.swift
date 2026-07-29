import Foundation
import UIKit
import UserNotifications
import FirebaseMessaging

final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()
    
    @Published var fcmToken: String?
    @Published var hasPermission = false
    
    private override init() {
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
        // TODO: Persist token to Firestore user document so Cloud Functions can target this device
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
