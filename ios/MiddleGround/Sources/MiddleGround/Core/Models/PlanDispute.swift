import Foundation

/// Somebody asking for a second look at a plan the two of them remember differently.
///
/// A disputed plan already settles nothing — it scores nothing either way and pays no stake,
/// which is the safe behaviour and stays. This is the entry point to a person, not a mechanism
/// that decides anything on its own. Nothing about raising one changes the plan.
///
/// **Kept apart from `reports` on purpose.** That queue means abuse, and its screen carries a
/// stated 24-hour review promise made under App Review guideline 1.2. Filing "we remember Tuesday
/// differently" into it would dilute that promise and would file a disagreement against somebody
/// as though they had been reported for misconduct. Two different things, two queues.
///
/// Like a report, it is evidence: append-only, never editable by the people it concerns, and an
/// operator may add a decision and nothing else.
struct PlanDispute: Identifiable, Hashable, Codable, Sendable {
    let id: String
    /// Who asked for the second look.
    let raisedBy: String
    let requestID: String
    /// What the plan was called, so a queue is readable without joining to requests.
    let planTitle: String
    /// Optional, and the only free text — capped like every other note in the app.
    let note: String?
    let at: Date

    /// What was decided, and by whom. Nil while nobody has looked.
    let resolution: ReportResolution?
    let resolvedBy: String?
    let resolvedAt: Date?

    var isResolved: Bool { resolution != nil }

    init(
        id: String = UUID().uuidString,
        raisedBy: String,
        requestID: String,
        planTitle: String,
        note: String? = nil,
        at: Date = Date(),
        resolution: ReportResolution? = nil,
        resolvedBy: String? = nil,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.raisedBy = raisedBy
        self.requestID = requestID
        self.planTitle = planTitle
        self.note = note
        self.at = at
        self.resolution = resolution
        self.resolvedBy = resolvedBy
        self.resolvedAt = resolvedAt
    }
}
