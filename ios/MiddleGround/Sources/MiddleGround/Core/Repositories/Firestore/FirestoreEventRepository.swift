import FirebaseAuth
import FirebaseFirestore
import Foundation

actor FirestoreEventRepository: EventRepository {
    /// Computed, not stored: constructing this type must not require FirebaseApp.configure().
    private var db: Firestore { Firestore.firestore() }
    private static let eventCollection = "events"
    private static let auditCollection = "admin_audit"
    private static let reportCollection = "reports"

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

    // MARK: - Reports

    /// Throws on purpose, unlike `record`: a user who taps Report is told whether it worked.
    func submitReport(_ report: ContentReport) async throws {
        try db.collection(Self.reportCollection)
            .document(report.id)
            .setData(from: ReportDTO(from: report))
    }

    func recentReports(limit: Int) async throws -> [ContentReport] {
        let snapshot = try await db.collection(Self.reportCollection)
            .order(by: "at", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: ReportDTO.self).toModel() }
    }

    /// Writes only the three resolution fields. The rules refuse anything else on a report, so a
    /// whole-document write would be rejected — and should be: the report itself is evidence and
    /// must stay exactly as it was filed.
    func resolveReport(id: String, as resolution: ReportResolution, by adminID: String) async throws {
        try await db.collection(Self.reportCollection)
            .document(id)
            .updateData([
                "resolution": resolution.rawValue,
                "resolvedBy": adminID,
                "resolvedAt": Timestamp(date: Date())
            ])
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
    /// When Firestore may delete this row: ninety days after it was written.
    ///
    /// A separate field because a TTL policy deletes a document as soon as the timestamp it points
    /// at is in the past — there is no offset. The policy used to point at `at`, which is the
    /// moment the event happened and is therefore *already* past on write, so every event was
    /// collected within about a day. Six users, twelve requests and five groups had produced an
    /// entirely empty `events` collection.
    ///
    /// `locations` and `presence` already had the right shape; this brings events into line.
    var expiresAt: Timestamp

    init(from event: AnalyticsEvent) {
        self.id = event.id
        self.userID = event.userID
        self.type = event.type.rawValue
        self.requestID = event.requestID
        self.relationshipID = event.relationshipID
        self.metadata = event.metadata
        self.at = Timestamp(date: event.at)
        self.expiresAt = Timestamp(date: event.at.addingTimeInterval(EventDTO.retention))
    }

    /// The ninety days the privacy policy promises.
    static let retention: TimeInterval = 90 * 24 * 60 * 60

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

private struct ReportDTO: Codable {
    @DocumentID var id: String?
    var reporterID: String
    var requestID: String
    var reportedUserID: String
    var reason: String
    var note: String?
    var at: Timestamp
    var resolution: String?
    var resolvedBy: String?
    var resolvedAt: Timestamp?

    init(from report: ContentReport) {
        self.id = report.id
        self.reporterID = report.reporterID
        self.requestID = report.requestID
        self.reportedUserID = report.reportedUserID
        self.reason = report.reason.rawValue
        self.note = report.note
        self.at = Timestamp(date: report.at)
        self.resolution = report.resolution?.rawValue
        self.resolvedBy = report.resolvedBy
        self.resolvedAt = report.resolvedAt.map { Timestamp(date: $0) }
    }

    func toModel() -> ContentReport? {
        guard let id, let reason = ReportReason(rawValue: reason) else { return nil }
        return ContentReport(
            id: id,
            reporterID: reporterID,
            requestID: requestID,
            reportedUserID: reportedUserID,
            reason: reason,
            note: note,
            at: at.dateValue(),
            resolution: resolution.flatMap(ReportResolution.init(rawValue:)),
            resolvedBy: resolvedBy,
            resolvedAt: resolvedAt?.dateValue()
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
