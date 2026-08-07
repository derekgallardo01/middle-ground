import Foundation

/// Whether a plan everyone said yes to is still alive.
///
/// A group agrees to something three weeks out and then nothing happens for twenty days, and by
/// the time it arrives half of them have privately assumed it is off. With two people you would
/// text; with five, everybody waits for somebody else to.
///
/// The app already had both ends of this and nothing in the middle. `remindBeforePlan` asks
/// "Still on?" sixteen hours before, `promptForAttendance` asks "did it happen?" four hours after,
/// and **between agreement and T-16h nothing fires at all, however far away the plan is** — which
/// is exactly the stretch a far-out plan dies in.
///
/// **Silence is measured against the runway, not against the clock.** Six days of quiet on a plan
/// a month away is a group getting on with their lives; the same six days on a plan next week is a
/// plan dissolving. Halving the runway is the whole idea, and it is one line.
///
/// Computed from fields already on the request document — nothing here costs a read. It carries
/// the sentence that explains it, because `ROADMAP.md` settled that an unexplainable score is not
/// worth showing: a bare ring tells somebody they are failing without telling them at what.
struct PlanMomentum: Equatable, Sendable {

    enum State: Equatable, Sendable {
        /// Not a dated, agreed plan — or close enough that the reminder already covers it.
        case notApplicable
        /// Agreed recently. Quiet is not a symptom yet.
        case early
        /// Somebody has spoken or confirmed recently, relative to how far off it is.
        case warm
        /// Gone quiet for longer than this plan's own runway justifies.
        case fading
        /// Quiet, and close enough that it will not survive being left alone.
        case atRisk
    }

    let state: State
    /// Why, in words somebody would say. Never shown without this.
    let reason: String

    /// Whether to offer the check-in. Deliberately only the two states that mean something is
    /// wrong — prompting a healthy plan is how a helpful feature becomes nagging.
    var wantsCheckIn: Bool { state == .fading || state == .atRisk }

    // MARK: - The thresholds, and why each one is where it is

    /// Inside this, `remindBeforePlan` already sends "Still on?" — asking twice is nagging.
    /// Matches the sixteen hours in `CloudFunctions/index.js`; if that moves, this moves.
    static let reminderWindow: TimeInterval = 16 * 3600

    /// Below this, quiet is just a normal week. Without a floor, a plan agreed on Monday for
    /// Wednesday would be "fading" by Tuesday morning.
    static let minimumSilence: TimeInterval = 3 * 86_400

    /// However long the runway, a fortnight of total silence is worth a word.
    static let maximumSilence: TimeInterval = 14 * 86_400

    /// Under this much time left, quiet stops being drift and starts being a plan nobody attends.
    static let closeWindow: TimeInterval = 7 * 86_400

    // MARK: - Building it

    static func from(request: Request, now: Date = Date()) -> PlanMomentum {
        guard request.status == .accepted, let time = request.proposedTime else {
            return PlanMomentum(state: .notApplicable, reason: "")
        }

        let remaining = time.timeIntervalSince(now)
        guard remaining > reminderWindow else {
            // Either it has passed, or the evening-before reminder owns it.
            return PlanMomentum(state: .notApplicable, reason: "")
        }

        let agreedAt = request.agreedAt ?? request.createdAt
        let lastHeard = [agreedAt, request.updatedAt, request.stillOn.values.max()]
            .compactMap { $0 }
            .max() ?? agreedAt

        let silence = now.timeIntervalSince(lastHeard)
        let runway = max(0, time.timeIntervalSince(agreedAt))
        // The plan's own patience: half its runway, and never more than a fortnight.
        let tolerated = max(minimumSilence, min(runway / 2, maximumSilence))

        let away = phrase(forDays: days(remaining))

        guard silence > tolerated else {
            if silence < minimumSilence && now.timeIntervalSince(agreedAt) < minimumSilence {
                return PlanMomentum(
                    state: .early,
                    reason: "Agreed \(phrase(forDays: days(now.timeIntervalSince(agreedAt)))) ago. \(away) to go."
                )
            }
            return PlanMomentum(
                state: .warm,
                reason: "Last talked about \(phrase(forDays: days(silence))) ago. \(away) to go."
            )
        }

        let quiet = phrase(forDays: days(silence))
        if remaining < closeWindow {
            return PlanMomentum(
                state: .atRisk,
                reason: "Nothing said in \(quiet), and it is \(away) away."
            )
        }
        return PlanMomentum(
            state: .fading,
            reason: "Agreed \(phrase(forDays: days(now.timeIntervalSince(agreedAt)))) ago. "
                + "Nothing since. \(away) to go."
        )
    }

    // MARK: - Words

    private static func days(_ interval: TimeInterval) -> Int {
        max(0, Int((interval / 86_400).rounded(.down)))
    }

    /// "today", "a day", "9 days", "3 weeks" — how somebody would say it out loud.
    private static func phrase(forDays count: Int) -> String {
        switch count {
        case 0: return "today"
        case 1: return "a day"
        case 2...13: return "\(count) days"
        case 14...20: return "2 weeks"
        case 21...27: return "3 weeks"
        default: return "\(count / 7) weeks"
        }
    }
}

extension Request {
    /// When this plan was agreed to.
    ///
    /// Read from the negotiation chain because **there is no `acceptedAt` field** and `updatedAt`
    /// is overwritten by every later edit — asking it "when did we agree" gets the time of the
    /// most recent message instead. The chain carries a timestamp per entry, so the answer is
    /// there; it has just never been asked for.
    var agreedAt: Date? {
        negotiationChain.last { $0.responseType == .accept }?.timestamp
    }

    /// Whether this person's "still on" is newer than the last change to the plan.
    ///
    /// A yes given before the time moved is not a yes to the new time, and showing it as a tick
    /// would put words in somebody's mouth.
    func hasCurrentStillOn(from userID: String) -> Bool {
        guard let said = stillOn[userID] else { return false }
        guard let lastChange = negotiationChain.last?.timestamp else { return true }
        return said >= lastChange
    }
}
