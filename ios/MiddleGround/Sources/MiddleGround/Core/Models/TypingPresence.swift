import Foundation

/// That somebody is composing something on a plan, right now.
///
/// Its own tiny document at `requests/{id}/presence/{uid}`, and that placement is the only reason
/// this is affordable. On the request document it would rewrite the whole plan — and, before the
/// conversation moved out, the entire message history with it — several times per person per
/// sentence, pushing all of it to every listener. Here it is a handful of bytes that nothing else
/// is listening to.
///
/// **Expiry is on the document, not in the client.** A phone that loses signal, is locked, or is
/// force-quit mid-sentence never gets to clear its own flag, and "Alex is typing…" that never goes
/// away is worse than no indicator at all. Anything older than `staleAfter` is ignored on read and
/// deleted by TTL on the server, so the failure mode is silence rather than a lie.
struct TypingPresence: Identifiable, Hashable, Codable, Sendable {
    let userID: String
    let startedAt: Date
    /// Server-enforced ceiling. Pinned in the rules so a client cannot claim to be typing for
    /// an hour.
    let expiresAt: Date

    var id: String { userID }

    /// How long a single "still typing" heartbeat stays true for.
    ///
    /// Long enough to survive the gap between keystrokes in a sentence, short enough that a
    /// dropped connection clears within a breath.
    static let staleAfter: TimeInterval = 8

    /// How often the client refreshes while someone keeps typing. Comfortably inside
    /// `staleAfter`, so an ordinary pause never flickers the indicator off.
    static let heartbeat: TimeInterval = 4

    init(userID: String, startedAt: Date = Date()) {
        self.userID = userID
        self.startedAt = startedAt
        self.expiresAt = startedAt.addingTimeInterval(Self.staleAfter)
    }

    init(userID: String, startedAt: Date, expiresAt: Date) {
        self.userID = userID
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    func hasExpired(at now: Date = Date()) -> Bool { expiresAt <= now }
}
