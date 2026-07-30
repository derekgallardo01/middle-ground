import Foundation

/// Persistence for product-usage events and the admin audit trail.
///
/// Reads are admin-only and writes are self-only; both are enforced in `firestore.rules`, not
/// here — this protocol is just the shape.
protocol EventRepository: Sendable {
    /// Records an event for the signed-in user. Never throws into a caller: analytics must not
    /// be able to fail a user action.
    func record(_ event: AnalyticsEvent) async

    // MARK: - Admin reads

    func recentEvents(limit: Int) async throws -> [AnalyticsEvent]
    func events(forUser userID: String, limit: Int) async throws -> [AnalyticsEvent]
    func eventCount(since: Date) async throws -> Int

    // MARK: - Audit trail

    /// Appends an immutable record that an admin viewed something. Rules forbid update/delete.
    func recordAudit(_ entry: AdminAuditEntry) async
    func recentAudit(limit: Int) async throws -> [AdminAuditEntry]
}

/// One admin access to user data. Append-only by design: this is the record of who looked at
/// what, which is the first thing anyone reviewing operator access will ask for.
struct AdminAuditEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let adminID: String
    let action: String
    let targetType: String
    let targetID: String
    let at: Date

    init(
        id: String = UUID().uuidString,
        adminID: String,
        action: String,
        targetType: String,
        targetID: String,
        at: Date = Date()
    ) {
        self.id = id
        self.adminID = adminID
        self.action = action
        self.targetType = targetType
        self.targetID = targetID
        self.at = at
    }
}

// MARK: - Mock

actor MockEventRepository: EventRepository {
    private var events: [AnalyticsEvent] = []
    private var audit: [AdminAuditEntry] = []

    func record(_ event: AnalyticsEvent) async {
        events.append(event)
    }

    func recentEvents(limit: Int) async throws -> [AnalyticsEvent] {
        Array(events.sorted { $0.at > $1.at }.prefix(limit))
    }

    func events(forUser userID: String, limit: Int) async throws -> [AnalyticsEvent] {
        Array(events.filter { $0.userID == userID }.sorted { $0.at > $1.at }.prefix(limit))
    }

    func eventCount(since: Date) async throws -> Int {
        events.filter { $0.at >= since }.count
    }

    func recordAudit(_ entry: AdminAuditEntry) async {
        audit.append(entry)
    }

    func recentAudit(limit: Int) async throws -> [AdminAuditEntry] {
        Array(audit.sorted { $0.at > $1.at }.prefix(limit))
    }
}
