import Foundation

/// Where a user's notification choices live.
///
/// A collection of their own, rather than a few fields on `users/{uid}`, because that document is
/// `allow get: if signedIn()` — readable by any signed-in user. What someone has chosen to be
/// interrupted about is nobody else's business. `user_tokens/{uid}` was the other candidate and
/// is worse: it is `allow read: if false`, so settings stored there could never be read back to
/// display them.
protocol NotificationSettingsRepository: Sendable {
    func settings(for userID: String) async throws -> NotificationSettings
    func save(_ settings: NotificationSettings, for userID: String) async throws
}

actor MockNotificationSettingsRepository: NotificationSettingsRepository {
    private var storage: [String: NotificationSettings] = [:]

    func settings(for userID: String) async throws -> NotificationSettings {
        storage[userID] ?? NotificationSettings()
    }

    func save(_ settings: NotificationSettings, for userID: String) async throws {
        storage[userID] = settings
    }
}
