import FirebaseFirestore
import Foundation

actor FirestoreNotificationSettingsRepository: NotificationSettingsRepository {
    /// Computed, not stored: constructing this type must not require FirebaseApp.configure().
    private var db: Firestore { Firestore.firestore() }
    private static let collection = "notification_settings"

    func settings(for userID: String) async throws -> NotificationSettings {
        let document = try await db.collection(Self.collection).document(userID).getDocument()
        guard let fields = document.data() as? [String: Bool] else { return NotificationSettings() }
        return NotificationSettings(fields: fields)
    }

    /// Merges, so a kind added in a later version does not get wiped by an older client that has
    /// never heard of it — the backend treats a missing field as on, which is the safe direction.
    func save(_ settings: NotificationSettings, for userID: String) async throws {
        try await db.collection(Self.collection)
            .document(userID)
            .setData(settings.fields, merge: true)
    }
}
