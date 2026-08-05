import Foundation

/// How reliably someone turns up to what they agreed to.
///
/// This is the "score" the roadmap keeps returning to — popularity score, missed reservations
/// subtract, cancelled three times in a row. It is computed rather than stored, from the
/// attendance confirmations and cancellations already on the requests, so there is no separate
/// number to keep in sync and nothing to tamper with independently of the record it comes from.
///
/// Four decisions are deliberate, and each one is a place this could quietly become unfair:
///
/// 1. **No score until there is enough to say.** A single missed plan is not a pattern, and
///    "0%" next to one data point is a libel, not a measurement.
/// 2. **Only late cancellations count.** Calling something off a week out is courtesy;
///    calling it off an hour before is the thing people actually mind.
/// 3. **Disputed plans score nothing.** If the two people disagree about whether it happened,
///    the app does not get to pick a winner — that is what an appeal is for.
/// 4. **Silence scores nothing.** An unanswered confirmation is not a no-show, or the score
///    punishes people for not opening an app.
struct ReliabilityScore: Equatable, Sendable {
    /// Plans both people confirmed happened.
    let attended: Int
    /// Plans this person said did not happen, and the other agreed.
    let missed: Int
    /// Plans this person called off close to the time.
    let lateCancellations: Int
    /// Consecutive cancellations, most recent first — the "three in a row" signal.
    let cancellationStreak: Int

    /// Cancelling within this window counts against reliability; earlier does not.
    static let lateCancellationWindow: TimeInterval = 24 * 60 * 60
    /// Below this many settled plans, no score is shown at all.
    static let minimumSample = 5
    /// Consecutive cancellations before it is worth saying something.
    static let concerningStreak = 3

    var settledCount: Int { attended + missed + lateCancellations }

    var hasEnoughData: Bool { settledCount >= Self.minimumSample }

    /// 0–100, or nil when there is not enough to say. Nil is a real answer, not a zero.
    var percentage: Int? {
        guard hasEnoughData else { return nil }
        return Int((Double(attended) / Double(settledCount) * 100).rounded())
    }

    var isCancellingRepeatedly: Bool { cancellationStreak >= Self.concerningStreak }

    /// Builds a score from one person's view of a set of requests.
    ///
    /// Only requests this person participates in, and only ones that reached a settled outcome —
    /// anything still being negotiated says nothing about whether they turn up.
    static func from(requests: [Request], userID: String, now: Date = Date()) -> ReliabilityScore {
        var attended = 0
        var missed = 0
        var lateCancellations = 0

        for request in requests where request.isParticipant(userID) {
            switch request.status {
            case .completed where request.isConfirmedComplete:
                attended += 1

            case .accepted where request.everyoneHasAnswered && !request.isDisputed:
                // Everyone answered and agreed it did not happen.
                if request.confirmations[userID] == .didNotHappen { missed += 1 }

            case .cancelled where request.creatorID == userID:
                if request.wasCancelledLate { lateCancellations += 1 }

            default:
                // Open, disputed, unanswered, declined, or somebody else's cancellation —
                // none of which says anything about this person's reliability.
                continue
            }
        }

        return ReliabilityScore(
            attended: attended,
            missed: missed,
            lateCancellations: lateCancellations,
            cancellationStreak: consecutiveCancellations(in: requests, by: userID)
        )
    }

    /// Cancellations at the end of this person's own recent history, newest first.
    ///
    /// Counts only requests they created: cancelling is something you do to your own plan, and
    /// the run breaks on the first plan they saw through.
    private static func consecutiveCancellations(in requests: [Request], by userID: String) -> Int {
        let theirs = requests
            .filter { $0.creatorID == userID && !$0.isOpen }
            .sorted { $0.updatedAt > $1.updatedAt }

        var streak = 0
        for request in theirs {
            guard request.status == .cancelled else { break }
            streak += 1
        }
        return streak
    }
}

extension ReliabilityScore {
    /// Whether one person's score may be shown to the others in a group.
    ///
    /// The roadmap carried this as an open question — "who can see someone's reliability score?"
    /// — while the answer already existed in a view model, where a second screen could have
    /// answered it differently without anybody noticing. It lives here now, beside the thing it
    /// governs.
    ///
    /// **Never inside a couple.** A score your partner can throw back at you is ammunition, not
    /// feedback, and it is a rule rather than a setting for that reason. The check is the member
    /// count via `type`, not the group's name, because a couple that calls itself something else
    /// is still two people.
    ///
    /// **Never in a group nobody has joined.** A "score" derived from plans with yourself is not
    /// a measurement of anything.
    ///
    /// `GroupFollowThrough` deliberately does not consult this: it reports on a group's plans
    /// rather than on a person, names nobody, and cannot be decomposed into per-person figures —
    /// so the ammunition problem this exists to prevent does not arise there.
    static func canBeSeen(in relationship: Relationship) -> Bool {
        relationship.type != .couple && relationship.isPaired
    }
}

extension Request {
    /// Called off close enough to the time that the other person had already planned around it.
    ///
    /// A plan with no time cannot be cancelled "late" — there was no moment to be late for.
    var wasCancelledLate: Bool {
        guard status == .cancelled, let time = proposedTime else { return false }
        return time.timeIntervalSince(updatedAt) < ReliabilityScore.lateCancellationWindow
    }
}
