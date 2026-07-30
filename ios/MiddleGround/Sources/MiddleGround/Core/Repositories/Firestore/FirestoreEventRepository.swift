import FirebaseAuth
import FirebaseFirestore
import Foundation

actor FirestoreEventRepository: EventRepository {
    /// Computed, not stored: constructing this type must not require FirebaseApp.configure().
    private var db: Firestore { Firestore.firestore() }
    private static let eventCollection = "events"
    private static let auditCollection = "admin_audit"

    // MARK: - Writes

    func record(_ event: AnalyticsEvent) async {
        // Deliberately swallows failures. An analytics write must never surface as a user-facing
        // error or roll back the action that triggered it.
        guard Auth.auth().currentUser != nil else { return }
        do {
            try db.collection(Self.eventCollection)
                .document(event.id)
                .setData(from: EventDTO(from: event))
        } catch {
            MGLog.storage.error("Event not recorded: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordAudit(_ entry: AdminAuditEntry) async {
        do {
            try db.collection(Self.auditCollection)
                .document(entry.id)
                .setData(from: AuditDTO(from: entry))
        } catch {
            MGLog.storage.error("Audit entry not recorded: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Admin reads (denied for non-admins by firestore.rules)

    func recentEvents(limit: Int) async throws -> [AnalyticsEvent] {
        let snapshot = try await db.collection(Self.eventCollection)
            .order(by: "at", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: EventDTO.self).toModel() }
    }

    func events(forUser userID: String, limit: Int) async throws -> [AnalyticsEvent] {
        let snapshot = try await db.collection(Self.eventCollection)
            .whereField("userID", isEqualTo: userID)
            .order(by: "at", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: EventDTO.self).toModel() }
    }

    func eventCount(since: Date) async throws -> Int {
        // Aggregation query: counts server-side without reading the documents.
        let query = db.collection(Self.eventCollection)
            .whereField("at", isGreaterThan: Timestamp(date: since))
        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    func recentAudit(limit: Int) async throws -> [AdminAuditEntry] {
        let snapshot = try await db.collection(Self.auditCollection)
            .order(by: "at", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: AuditDTO.self).toModel() }
    }
}

// MARK: - DTOs

private struct EventDTO: Codable {
    @DocumentID var id: String?
    var userID: String
    var type: String
    var requestID: String?
    var relationshipID: String?
    var metadata: [String: String]
    var at: Timestamp

    init(from event: AnalyticsEvent) {
        self.id = event.id
        self.userID = event.userID
        self.type = event.type.rawValue
        self.requestID = event.requestID
        self.relationshipID = event.relationshipID
        self.metadata = event.metadata
        self.at = Timestamp(date: event.at)
    }

    func toModel() -> AnalyticsEvent? {
        guard let id, let eventType = EventType(rawValue: type) else { return nil }
        return AnalyticsEvent(
            id: id,
            userID: userID,
            type: eventType,
            requestID: requestID,
            relationshipID: relationshipID,
            metadata: metadata,
            at: at.dateValue()
        )
    }
}

private struct AuditDTO: Codable {
    @DocumentID var id: String?
    var adminID: String
    var action: String
    var targetType: String
    var targetID: String
    var at: Timestamp

    init(from entry: AdminAuditEntry) {
        self.id = entry.id
        self.adminID = entry.adminID
        self.action = entry.action
        self.targetType = entry.targetType
        self.targetID = entry.targetID
        self.at = Timestamp(date: entry.at)
    }

    func toModel() -> AdminAuditEntry? {
        guard let id else { return nil }
        return AdminAuditEntry(
            id: id,
            adminID: adminID,
            action: action,
            targetType: targetType,
            targetID: targetID,
            at: at.dateValue()
        )
    }
}
