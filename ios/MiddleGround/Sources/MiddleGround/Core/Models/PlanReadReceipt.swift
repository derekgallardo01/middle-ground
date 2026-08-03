import Foundation

/// How far somebody has read a plan.
///
/// **Per plan, not per message.** The distinction is the whole of it: "Alex has seen this plan"
/// answers a question people actually have, while a tick against every individual line imports
/// the thing that makes group chats stressful — being watched reading, and owing a reply the
/// moment you look.
///
/// It is also the weaker of two signals the app already carries. `Request.awaitingResponseFrom`
/// says who still owes an *answer*, which matters more than who has looked; this only fills the
/// gap where somebody has read a conversation they are not required to answer.
///
/// Lives at `requests/{id}/reads/{uid}` — one small document per person per plan, written at most
/// once per visit rather than once per message.
struct PlanReadReceipt: Identifiable, Hashable, Codable, Sendable {
    let userID: String
    /// When they last had this plan open.
    let readAt: Date

    var id: String { userID }

    /// Whether this receipt covers `date` — i.e. they have seen everything up to it.
    func hasSeen(_ date: Date) -> Bool { readAt >= date }
}
