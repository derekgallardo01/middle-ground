import Foundation

/// Points both people put on a plan actually happening.
///
/// "Motivation betting" from the brainstorm, resolved as **points rather than money** — your
/// call, and the right one: real money would make this a payments feature under App Review 3.1.1
/// and quite possibly a gambling one, for a mechanic whose whole value is the small social nudge
/// of having something on it.
///
/// It settles on attendance confirmation, so it inherits every fairness decision made there:
/// silence settles nothing, a disagreement settles nothing, and one person cannot resolve it
/// alone. A stake collectable by simply asserting the other person did not turn up would be
/// worse than no stake at all.
struct Stake: Codable, Hashable, Sendable {
    /// Who proposed it. Only the other person can accept.
    let proposedBy: String
    /// Points each side risks. Equal on both sides — an uneven stake is a bet, not a nudge.
    let points: Int
    /// Nil until the other person agrees. An unaccepted stake never settles.
    var acceptedBy: String?

    static let options = [10, 25, 50]

    var isAccepted: Bool { acceptedBy != nil }

    func canAccept(_ userID: String) -> Bool { acceptedBy == nil && userID != proposedBy }

}

enum StakeSettlement: String, Codable, Hashable, Sendable {
    /// Everyone confirmed it happened: stake returned, plus the same again as a reward.
    case kept
    /// Agreed it did not happen: both forfeit what they staked.
    case forfeited

    var displayName: String {
        switch self {
        case .kept: return "You both turned up"
        case .forfeited: return "It didn't happen"
        }
    }

    /// XP change per person, as a multiple of the staked points.
    ///
    /// Winning pays the stake back as a bonus rather than doubling anything, so the upside is
    /// proportional to the risk taken and the downside is exactly what was put in.
    var multiplier: Int {
        switch self {
        case .kept: return 1
        case .forfeited: return -1
        }
    }
}

extension Request {
    /// How the stake resolved, derived from the confirmations rather than stored.
    ///
    /// Deriving it is what makes it safe. A stored settlement would have to be writable by
    /// whoever confirms attendance — and a client that can write it can claim it, setting
    /// "kept" while only they had answered. Computing it from the confirmation record means
    /// there is nothing to forge: the outcome is whatever the two answers already say.
    ///
    /// Both sides win or both sides lose, never one at the other's expense. The attendance
    /// record says *whether a plan happened*, never whose fault it was, so paying one person out
    /// of the other's stake would mean inventing a finding the data does not contain.
    var stakeSettlement: StakeSettlement? {
        guard let stake, stake.isAccepted, everyoneHasAnswered, !isDisputed else { return nil }
        return isConfirmedComplete ? .kept : .forfeited
    }

    /// XP this person gains or loses from the stake, once it has resolved.
    func stakeOutcome(for userID: String) -> Int {
        guard isParticipant(userID), let stake, let settlement = stakeSettlement else { return 0 }
        return stake.points * settlement.multiplier
    }
}
