import Foundation

/// A kind of push, and therefore a thing that can be switched off.
///
/// The raw values are the field names in `notification_settings/{uid}`, and they are matched by
/// string in `CloudFunctions/push.js`. Renaming a case silently un-mutes everyone who had muted
/// it, because the backend would look up a field nobody writes and find nothing — and a missing
/// field means on.
enum NotificationKind: String, CaseIterable, Identifiable, Sendable {
    case newRequest
    case response
    case confirmPlan
    case planCancelled
    case weeklyNudge
    /// Somebody said something on a plan, as opposed to answering it.
    case message

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newRequest: return "New requests"
        case .response: return "Replies"
        case .confirmPlan: return "Did it happen?"
        case .planCancelled: return "Cancellations"
        case .weeklyNudge: return "Weekly nudge"
        case .message: return "Messages"
        }
    }

    var explanation: String {
        switch self {
        case .newRequest: return "Someone asks you to do something"
        case .response: return "Someone accepts, declines or counters"
        case .confirmPlan: return "A few hours after a plan, to confirm it happened"
        case .planCancelled: return "A plan you agreed to is called off"
        case .weeklyNudge: return "A reminder when a group has nothing planned"
        // Its own switch on purpose: talk is far more frequent than decisions, and bundling the
        // two would make people mute both to escape one.
        case .message: return "Someone says something on a plan"
        }
    }
}

/// Which kinds of push someone wants.
///
/// Absence means yes, everywhere — no stored document, no stored key, and a read that failed all
/// mean the notification sends. Everyone who predates this screen keeps exactly the behaviour
/// they had, and there is nothing to migrate. Defaulting the other way would have silently muted
/// every existing user the moment this shipped.
struct NotificationSettings: Codable, Sendable, Equatable {
    private var disabled: Set<String>

    init(disabled: Set<String> = []) {
        self.disabled = disabled
    }

    func isEnabled(_ kind: NotificationKind) -> Bool {
        !disabled.contains(kind.rawValue)
    }

    mutating func set(_ kind: NotificationKind, enabled: Bool) {
        if enabled {
            disabled.remove(kind.rawValue)
        } else {
            disabled.insert(kind.rawValue)
        }
    }

    /// The document as Firestore stores it: one boolean per kind.
    ///
    /// Every kind is written, including the enabled ones, so switching something back on clears
    /// the `false` rather than leaving it behind. A partial write would need field deletion to
    /// undo a mute, which is a sharper tool than this needs.
    var fields: [String: Bool] {
        Dictionary(uniqueKeysWithValues: NotificationKind.allCases.map { ($0.rawValue, isEnabled($0)) })
    }

    init(fields: [String: Bool]) {
        disabled = Set(fields.filter { !$0.value }.keys)
    }
}
