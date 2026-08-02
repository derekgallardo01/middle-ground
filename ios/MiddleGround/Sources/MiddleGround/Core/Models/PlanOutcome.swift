import Foundation

/// What became of one plan, recorded once, as an anonymous fact.
///
/// Reliability is *computed* — `ReliabilityScore.from(requests:)` derives it at read time from
/// the live request documents. That is the right design for a score shown to a user, and a
/// useless one for answering "of the plans people agreed to, how many actually happened?" a year
/// from now: requests are deleted with the account that owned them, and `events` carries a
/// 90-day TTL. Both are correct behaviours that also destroy the evidence. Follow-through cannot
/// be reconstructed after the fact, so it has to be written down as it happens.
///
/// **This record deliberately carries no `userID` and no `requestID`.** That is not squeamishness,
/// it is what lets the row survive honestly: the Privacy Policy promises that everything tied to
/// an account is erased when the account is deleted, and that usage events are deleted after 90
/// days. A per-user outcome log kept indefinitely would make both statements false. A row that
/// cannot be traced to a person is not personal data, so it can be kept — and aggregate rates are
/// the only thing the question needs anyway.
///
/// The fields that remain are the ones that make a rate interesting rather than identifying: how
/// many people were on it, what kind of plan it was, and how close to the time a cancellation
/// came.
struct PlanOutcome: Codable, Sendable, Equatable {
    let outcome: PlanOutcomeType
    /// Party size. The number a restaurant would care about, and the number that makes
    /// "groups of three behave differently from pairs" checkable rather than asserted.
    let groupSize: Int
    let category: RequestCategory
    /// A plan with no proposed time cannot be attended late or cancelled late.
    let hadProposedTime: Bool
    /// Hours between the action and the plan's time, floored. Negative means after the fact.
    /// Nil when there was no time to measure against.
    let hoursBeforePlan: Int?
    let at: Date

    init(
        outcome: PlanOutcomeType,
        groupSize: Int,
        category: RequestCategory,
        hadProposedTime: Bool,
        hoursBeforePlan: Int?,
        at: Date = Date()
    ) {
        self.outcome = outcome
        self.groupSize = groupSize
        self.category = category
        self.hadProposedTime = hadProposedTime
        self.hoursBeforePlan = hoursBeforePlan
        self.at = at
    }

    /// Derives the row from the request at the moment it settled.
    ///
    /// `now` is the moment of the action, not the plan's time — the distance between the two is
    /// the whole point of separating an early cancellation from a late one.
    static func from(
        _ request: Request,
        outcome: PlanOutcomeType,
        now: Date = Date()
    ) -> PlanOutcome {
        let hours = request.proposedTime.map {
            Int(($0.timeIntervalSince(now) / 3600).rounded(.down))
        }
        return PlanOutcome(
            outcome: outcome,
            groupSize: request.allParticipantIDs.count,
            category: request.category,
            hadProposedTime: request.proposedTime != nil,
            hoursBeforePlan: hours,
            at: now
        )
    }
}

/// That someone went looking for a table on a plan they had already agreed to.
///
/// The other half of the booking argument, and the half a partner cannot see for themselves: a
/// tap here is a group with a date, a time and a party size deciding they want a reservation. It
/// is recorded under the same rule as `PlanOutcome` — no user, no request, nothing to trace — and
/// for the same reason: it cannot be reconstructed later, and keeping it any other way would
/// contradict what the Privacy Policy promises about deletion.
struct BookingIntent: Codable, Sendable, Equatable {
    /// Which provider produced the link. Distinguishes a curated OpenTable web link from a real
    /// partner integration once one exists.
    let provider: String
    let groupSize: Int
    let category: RequestCategory
    let hoursBeforePlan: Int?
    let at: Date

    init(
        provider: String,
        groupSize: Int,
        category: RequestCategory,
        hoursBeforePlan: Int?,
        at: Date = Date()
    ) {
        self.provider = provider
        self.groupSize = groupSize
        self.category = category
        self.hoursBeforePlan = hoursBeforePlan
        self.at = at
    }

    static func from(_ request: Request, provider: String, now: Date = Date()) -> BookingIntent {
        BookingIntent(
            provider: provider,
            groupSize: request.allParticipantIDs.count,
            category: request.category,
            hoursBeforePlan: request.proposedTime.map {
                Int(($0.timeIntervalSince(now) / 3600).rounded(.down))
            },
            at: now
        )
    }
}

/// The five states worth counting, plus the one the app refuses to decide.
///
/// `agreed` is the denominator. Without it every other number is a count with nothing to divide
/// by, and "how many plans happen" cannot be answered at all.
enum PlanOutcomeType: String, Codable, Sendable, CaseIterable {
    /// Everyone said yes. Recorded when the plan reaches `.accepted`.
    case agreed
    /// Everyone confirmed afterwards that it happened.
    case attended
    /// Called off outside the late window — courtesy, not a broken promise.
    case cancelledEarly = "cancelled_early"
    /// Called off inside `ReliabilityScore.lateCancellationWindow`.
    case cancelledLate = "cancelled_late"
    /// Everyone answered, and they agreed it did not happen.
    case noShowed = "no_showed"
    /// People disagreed about whether it happened. Counted, never scored — the app does not
    /// pick a winner, and dropping these would quietly bias the rate upward.
    case disputed
}
