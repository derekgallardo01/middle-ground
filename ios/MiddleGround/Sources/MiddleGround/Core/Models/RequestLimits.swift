import Foundation

/// The refusals and the caps — the two things about a request that are not the request.
///
/// Split out of `Request.swift` for the 500-line limit, the same way the trip and time-zone
/// derivations were. Nothing here changed in the move.

enum RequestError: LocalizedError, Equatable {
    case notAllowedToRespond
    case notAllowedToCancel
    case notAllowedToConfirm
    case notAllowedToStake
    case notAllowedToInvite
    case inviteNotFound

    var errorDescription: String? {
        switch self {
        case .notAllowedToRespond:
            return "Only the person this was sent to can respond."
        case .notAllowedToCancel:
            return "Only the person who sent this can cancel it."
        case .notAllowedToConfirm:
            return "This plan isn't ready to confirm yet."
        case .notAllowedToStake:
            return "You can't put points on this plan."
        case .notAllowedToInvite:
            return "Only the person who created this plan can invite someone to it."
        case .inviteNotFound:
            return "That invite code doesn't match a plan."
        }
    }
}

/// Caps on anything a user types.
///
/// Only "not empty" was ever checked, so a long paste sailed through to Firestore and failed
/// against the 1 MB document limit — surfacing as a generic "Failed to send" with the text
/// lost. The negotiation chain makes that worse: every message is appended to the *same*
/// document, so the ceiling is shared across the whole conversation.
enum RequestLimits {
    static let title = 120
    static let details = 1_000
    static let message = 1_000
    static let reportNote = 500
    /// Group names sit in pickers and single-line rows, so they are capped far shorter.
    static let groupName = 40
    /// A place name, not an address essay.
    static let location = 120

    /// Trims to `limit` without splitting a grapheme cluster (an emoji stays whole).
    static func clamp(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit))
    }
}
