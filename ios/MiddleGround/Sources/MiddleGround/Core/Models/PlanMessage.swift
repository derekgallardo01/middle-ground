import Foundation

/// Something said about a plan, as opposed to something decided about it.
///
/// Lives in `requests/{id}/messages/{id}` rather than in `Request.negotiationChain`, and the split
/// is not stylistic. Two facts force it:
///
/// 1. **The chain is an array field on the request document.** Every message rewrites the whole
///    document and re-pushes it to every listener, and the document caps at 1 MiB. That is fine
///    for the handful of answers a decision takes and hopeless for conversation.
/// 2. **Security rules cannot query a subcollection.** They have `get()` and `exists()` for a
///    known path and nothing else, so `isMyTurn()` and friends can only be computed from data on
///    the request document itself.
///
/// Together those say exactly where the line goes: decisions stay on the document, where the
/// rules can see them and the volume is bounded; conversation lives here, where it can grow.
///
/// `parentID` is the thread. A reply points at the message it answers; a top-level message points
/// at nothing. Threading conversation and not decisions is deliberate — a plan has one decision
/// to make, and letting that fork is how a group chat loses the plot.
struct PlanMessage: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let senderID: String
    let text: String
    /// The message this replies to, if it is a reply.
    let parentID: String?
    let at: Date

    init(
        id: String = UUID().uuidString,
        senderID: String,
        text: String,
        parentID: String? = nil,
        at: Date = Date()
    ) {
        self.id = id
        self.senderID = senderID
        self.text = text
        self.parentID = parentID
        self.at = at
    }

    var isReply: Bool { parentID != nil }
}

/// One line of the plan's transcript, from either source.
///
/// The screen shows decisions and conversation interleaved, because that is how it reads to a
/// person — "Sam suggested Sunday / Alex: can't do Sunday, Monday?" is one conversation even
/// though the two halves are stored apart for reasons no user should ever have to know.
enum TranscriptEntry: Identifiable, Hashable, Sendable {
    case decision(NegotiationMessage)
    case message(PlanMessage)

    var id: String {
        switch self {
        case .decision(let message): return "d_\(message.id)"
        case .message(let message): return "m_\(message.id)"
        }
    }

    var senderID: String {
        switch self {
        case .decision(let message): return message.senderID
        case .message(let message): return message.senderID
        }
    }

    var timestamp: Date {
        switch self {
        case .decision(let message): return message.timestamp
        case .message(let message): return message.at
        }
    }

    var text: String? {
        switch self {
        case .decision(let message): return message.text
        case .message(let message): return message.text
        }
    }

    /// Replies are collapsed under their parent rather than shown inline in the timeline.
    var parentID: String? {
        switch self {
        case .decision: return nil
        case .message(let message): return message.parentID
        }
    }

    /// Builds the interleaved transcript, oldest first, with replies left out of the top level.
    static func transcript(
        decisions: [NegotiationMessage],
        messages: [PlanMessage]
    ) -> [TranscriptEntry] {
        let entries = decisions.map(TranscriptEntry.decision)
            + messages.filter { !$0.isReply }.map(TranscriptEntry.message)
        return entries.sorted { $0.timestamp < $1.timestamp }
    }

    /// Replies to one message, oldest first.
    static func replies(to parentID: String, in messages: [PlanMessage]) -> [PlanMessage] {
        messages.filter { $0.parentID == parentID }.sorted { $0.at < $1.at }
    }
}
