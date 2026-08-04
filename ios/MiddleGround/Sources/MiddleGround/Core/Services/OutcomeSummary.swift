import Foundation

/// What share of agreed plans actually happen — the number the partnership conversation runs on.
///
/// `docs/partnerships/opentable.md` offers exactly this in return for booking access, and calls
/// the reliability signal "the one worth protecting in negotiation". It has been recorded on every
/// agreement, attendance and cancellation since 2 August 2026 and, until now, read by nothing.
///
/// Aggregate only, and necessarily so: a `PlanOutcome` carries no user and no request, so this can
/// say what proportion of plans happen and cannot say whose. That is the same property that lets
/// the rows survive account deletion honestly. What a *user* sees about their own group is
/// `GroupFollowThrough`, computed from their own requests.
///
/// Nothing here can be reconstructed for dates before collection began — a caveat worth repeating
/// whenever the figure is quoted.
struct OutcomeSummary: Equatable, Sendable {
    let agreed: Int
    let attended: Int
    let cancelledEarly: Int
    let cancelledLate: Int
    let noShowed: Int
    let disputed: Int

    /// Plans that reached an answer, either way. `agreed` is the denominator's ancestor, not part
    /// of it: every settled plan was agreed first, so counting both would count each plan twice.
    var settled: Int { attended + cancelledEarly + cancelledLate + noShowed }

    /// The headline: of the plans that settled, how many happened. Nil below a usable sample.
    var followThroughPercentage: Int? {
        guard settled >= 10 else { return nil }
        return Int((Double(attended) / Double(settled) * 100).rounded())
    }

    /// The number a restaurant cares about most: called off close enough to the time that the
    /// table went empty.
    var lateCancellationPercentage: Int? {
        guard settled >= 10 else { return nil }
        return Int((Double(cancelledLate) / Double(settled) * 100).rounded())
    }

    /// How many more settled plans before the figures mean anything.
    var untilMeaningful: Int { max(0, 10 - settled) }

    static func from(_ outcomes: [PlanOutcome]) -> OutcomeSummary {
        var counts: [PlanOutcomeType: Int] = [:]
        for outcome in outcomes {
            counts[outcome.outcome, default: 0] += 1
        }
        return OutcomeSummary(
            agreed: counts[.agreed] ?? 0,
            attended: counts[.attended] ?? 0,
            cancelledEarly: counts[.cancelledEarly] ?? 0,
            cancelledLate: counts[.cancelledLate] ?? 0,
            noShowed: counts[.noShowed] ?? 0,
            disputed: counts[.disputed] ?? 0
        )
    }

    /// The same figure sliced by party size, which is how a restaurant reads it — a two-top and
    /// a party of six are different risks.
    static func byPartySize(_ outcomes: [PlanOutcome]) -> [(size: Int, summary: OutcomeSummary)] {
        Dictionary(grouping: outcomes, by: \.groupSize)
            .map { (size: $0.key, summary: .from($0.value)) }
            .sorted { $0.size < $1.size }
    }

    static func byCategory(_ outcomes: [PlanOutcome]) -> [(category: RequestCategory, summary: OutcomeSummary)] {
        Dictionary(grouping: outcomes, by: \.category)
            .map { (category: $0.key, summary: .from($0.value)) }
            .sorted { $0.summary.settled > $1.summary.settled }
    }
}
