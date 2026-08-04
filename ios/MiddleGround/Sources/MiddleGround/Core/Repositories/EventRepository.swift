import Foundation

/// Persistence for product-usage events, abuse reports, and the admin audit trail.
///
/// All three are operator-facing records written by the client and read only by an admin;
/// that asymmetry is enforced in `firestore.rules`, not here — this protocol is just the shape.
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

    // MARK: - Abuse reports

    /// Files a report. Throws, unlike `record` — the user is told whether it went through.
    func submitReport(_ report: ContentReport) async throws
    func recentReports(limit: Int) async throws -> [ContentReport]

    /// Records what was decided about a report, and who decided it. Admin-only, enforced by the
    /// security rules rather than only here.
    func resolveReport(id: String, as resolution: ReportResolution, by adminID: String) async throws
}

/// A user's report of content someone sent them.
///
/// Required by App Review guideline 1.2: an app carrying user-generated content needs a way to
/// report it and a way to get away from the person who sent it. The second half is
/// `RelationshipService.leave`.
struct ContentReport: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let reporterID: String
    let requestID: String
    /// Kept so an admin can find the content without the reporter having to describe it.
    let reportedUserID: String
    let reason: ReportReason
    let note: String?
    let at: Date

    /// What was decided about it, and by whom. Nil means nobody has looked yet.
    ///
    /// The reports screen quoted a 24-hour review promise (App Review 1.2) over a list with no
    /// action on it at all — nothing could be marked done, so a queue of a hundred reports and a
    /// queue of one looked identical and every report stayed unread forever.
    let resolution: ReportResolution?
    let resolvedBy: String?
    let resolvedAt: Date?

    var isResolved: Bool { resolution != nil }

    init(
        id: String = UUID().uuidString,
        reporterID: String,
        requestID: String,
        reportedUserID: String,
        reason: ReportReason,
        note: String? = nil,
        at: Date = Date(),
        resolution: ReportResolution? = nil,
        resolvedBy: String? = nil,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.reporterID = reporterID
        self.requestID = requestID
        self.reportedUserID = reportedUserID
        self.reason = reason
        self.note = note
        self.at = at
        self.resolution = resolution
        self.resolvedBy = resolvedBy
        self.resolvedAt = resolvedAt
    }
}

/// What an operator decided about a report.
///
/// Two outcomes, not five. The distinction that matters for the 24-hour promise is "somebody has
/// looked at this" versus "nobody has"; finer grades of severity are a moderation policy, and
/// inventing one here would be pretending to a process that does not exist yet.
enum ReportResolution: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Acted on: the content or the account was dealt with outside the app.
    case actioned
    /// Looked at and judged to need nothing.
    case dismissed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .actioned: return "Actioned"
        case .dismissed: return "Dismissed"
        }
    }
}

enum ReportReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case harassment
    case sexualContent
    case threat
    case spam
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .harassment: return "Harassment or bullying"
        case .sexualContent: return "Unwanted sexual content"
        case .threat: return "Threat or violence"
        case .spam: return "Spam"
        case .other: return "Something else"
        }
    }
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

    private var reports: [ContentReport] = []

    func submitReport(_ report: ContentReport) async throws {
        reports.append(report)
    }

    func recentReports(limit: Int) async throws -> [ContentReport] {
        Array(reports.sorted { $0.at > $1.at }.prefix(limit))
    }

    func resolveReport(id: String, as resolution: ReportResolution, by adminID: String) async throws {
        guard let index = reports.firstIndex(where: { $0.id == id }) else { return }
        let existing = reports[index]
        reports[index] = ContentReport(
            id: existing.id,
            reporterID: existing.reporterID,
            requestID: existing.requestID,
            reportedUserID: existing.reportedUserID,
            reason: existing.reason,
            note: existing.note,
            at: existing.at,
            resolution: resolution,
            resolvedBy: adminID,
            resolvedAt: Date()
        )
    }
}
