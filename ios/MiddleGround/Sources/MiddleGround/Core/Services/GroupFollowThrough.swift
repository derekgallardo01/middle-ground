import Foundation

/// How often the plans a group agrees to actually happen.
///
/// The app's entire claim is that a plan here becomes a decision rather than scrolling away. This
/// is that claim, measured, and until now nothing in the app said it back to the people using it.
///
/// **Why this is shown to couples when the scoreboard is not.** The house rule is that couples are
/// never scored, because a score your partner can throw back at you is ammunition rather than
/// feedback. That rule is about *ranking people against each other* — `GroupScoreboard` refuses to
/// exist below three members for exactly that reason. This number ranks nobody: it has no per-person
/// breakdown, cannot be decomposed into one, and is equally true of everyone in the group. Two
/// people finding out that half their plans evaporate is the product working.
///
/// Computed from the group's own requests, not from `plan_outcomes`. Those rows deliberately carry
/// no user and no request — that anonymity is what lets them survive account deletion honestly, and
/// it also means they can only ever answer an aggregate question, never "how are *we* doing".
struct GroupFollowThrough: Equatable, Sendable {
    /// Plans everyone agreed happened.
    let happened: Int
    /// Plans that were agreed and then did not happen — called off, or nobody turned up.
    let fellThrough: Int

    /// Below this many settled plans there is nothing honest to say. Same reasoning as
    /// `ReliabilityScore.minimumSample`: a percentage over two data points is a rumour.
    static let minimumSample = 5

    var settledCount: Int { happened + fellThrough }

    var hasEnoughData: Bool { settledCount >= Self.minimumSample }

    /// 0–100, or nil when there is not enough to say. Nil is a real answer, not a zero.
    var percentage: Int? {
        guard hasEnoughData else { return nil }
        return Int((Double(happened) / Double(settledCount) * 100).rounded())
    }

    /// How many more settled plans before a figure appears, for the "not yet" copy.
    var plansUntilShown: Int { max(0, Self.minimumSample - settledCount) }

    /// Builds the figure for one group from the requests the viewer can already see.
    ///
    /// A request belongs to this group when somebody else in it is on the plan. Matching on all
    /// members would miss the ordinary case of a four-person group where three of you went.
    static func from(relationship: Relationship, requests: [Request]) -> GroupFollowThrough {
        let members = Set(relationship.participantIDs)
        var happened = 0
        var fellThrough = 0

        for request in requests {
            let participants = Set(request.allParticipantIDs)
            guard participants.intersection(members).count >= 2 else { continue }

            switch request.status {
            case .completed where request.isConfirmedComplete:
                happened += 1

            case .accepted where request.everyoneHasAnswered && !request.isDisputed:
                // Everyone answered, and between them said it did not happen.
                fellThrough += 1

            case .cancelled where request.wasEverAgreed:
                // Only a plan that was actually agreed can fall through. Calling off something
                // nobody had said yes to is a plan that never existed, not a broken one.
                fellThrough += 1

            default:
                // Open, disputed, declined, or unanswered — none of which is a settled outcome.
                continue
            }
        }

        return GroupFollowThrough(happened: happened, fellThrough: fellThrough)
    }
}

extension Request {
    /// Whether anybody ever accepted this plan.
    ///
    /// Read from the negotiation chain rather than the status, because the status has moved on by
    /// the time this matters — a cancelled plan says `.cancelled` whether it was agreed first or
    /// called off while still pending.
    var wasEverAgreed: Bool {
        negotiationChain.contains { $0.responseType == .accept }
    }
}
