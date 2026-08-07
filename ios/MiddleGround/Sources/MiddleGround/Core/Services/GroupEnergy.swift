import Foundation

/// Whether a group is still a group.
///
/// `GroupFollowThrough` answers "do the plans we agree to happen". This answers the slower
/// question underneath it: **are we still doing things together at all.** A group can have
/// flawless follow-through and be dead, because it has agreed to nothing since March.
///
/// Built from what actually happened, never from activity. Rewarding messages would make a chatty
/// group that never meets look healthier than a quiet one that meets every fortnight, and it is
/// the second group the product is for.
///
/// **Why a couple sees this and the scoreboard is hidden from them.** Same reasoning as
/// `GroupFollowThrough`: the house rule is about *ranking people against each other*, and this
/// ranks nobody. It has no per-person breakdown, cannot be decomposed into one, and is equally
/// true of everybody in the group. Two people noticing they have not seen each other since March
/// is the product working.
///
/// Computed from the requests the viewer can already see — the Activities tab has them loaded
/// before this is called, so nothing here costs a read.
struct GroupEnergy: Equatable, Sendable {

    enum Level: Int, Equatable, Sendable, Comparable {
        /// Nothing has happened and nothing is planned. Not a verdict — an absence of evidence.
        case notEnoughYet = 0
        /// A long time since anything, and nothing in the diary.
        case cooling = 1
        /// Ticking over.
        case steady = 2
        /// Seeing each other, and something ahead.
        case warm = 3

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let level: Level
    /// Why, in a sentence. `ROADMAP.md` settled that an unexplainable score is not worth
    /// showing — a ring on its own tells somebody they are failing without telling them at what.
    let reason: String
    /// Days since the group last did something together, when they ever have.
    let daysSinceTogether: Int?
    /// Plans agreed and still ahead.
    let upcomingCount: Int

    /// 0–1 for `GrowthRing`, or nil when there is nothing honest to draw.
    var ringProgress: Double? {
        guard level != .notEnoughYet else { return nil }
        return Double(level.rawValue) / Double(Level.warm.rawValue)
    }

    // MARK: - Where the lines are

    /// Seeing each other inside a month is a group that is working.
    static let warmWithin: TimeInterval = 30 * 86_400
    /// Past two months with nothing planned, "steady" would be a kind word rather than a true one.
    static let coolingAfter: TimeInterval = 60 * 86_400

    // MARK: - Building it

    static func from(
        relationship: Relationship,
        requests: [Request],
        now: Date = Date()
    ) -> GroupEnergy {
        let members = Set(relationship.participantIDs)

        // Same attribution as `GroupFollowThrough`: a plan belongs to this group when two of its
        // members are on it. Matching on everybody would miss the ordinary case of a group of four
        // where three of them went.
        let ours = requests.filter {
            Set($0.allParticipantIDs).intersection(members).count >= 2
        }

        let lastTogether = ours
            .filter { $0.status == .completed && $0.isConfirmedComplete }
            .compactMap { $0.proposedTime ?? $0.updatedAt }
            .filter { $0 <= now }
            .max()

        let upcoming = ours.filter { request in
            guard request.status == .accepted, let time = request.proposedTime else { return false }
            return time > now
        }.count

        let gap = lastTogether.map { now.timeIntervalSince($0) }
        let days = gap.map { max(0, Int(($0 / 86_400).rounded(.down))) }

        // Nothing behind and nothing ahead. Saying "cooling" here would be scoring a group for
        // having just formed.
        guard lastTogether != nil || upcoming > 0 else {
            return GroupEnergy(
                level: .notEnoughYet,
                reason: "Nothing to go on yet — make a plan and this fills in.",
                daysSinceTogether: nil,
                upcomingCount: 0
            )
        }

        var level: Level
        switch gap {
        case .some(let interval) where interval <= warmWithin: level = .warm
        case .some(let interval) where interval <= coolingAfter: level = .steady
        case .some: level = .cooling
        case .none: level = .steady   // never met, but something is booked
        }

        // Something in the diary is worth a step: a group with a date set is not cooling, whatever
        // the gap behind it says.
        if upcoming > 0, level < .warm {
            level = Level(rawValue: level.rawValue + 1) ?? .warm
        }

        // And plans that keep evaporating are worth one back. Only when there is enough to say so
        // — `GroupFollowThrough` returns nil rather than zero below its minimum for a reason.
        let followThrough = GroupFollowThrough.from(relationship: relationship, requests: ours)
        // Split rather than parenthesised: written as one condition,
        // `percentage < 50, level > .cooling` parses as generic angle brackets, and the
        // parentheses that fix it are the kind SwiftLint asks you to take back out.
        if let percentage = followThrough.percentage, percentage < 50 {
            if level > .cooling {
                level = Level(rawValue: level.rawValue - 1) ?? .cooling
            }
        }

        return GroupEnergy(
            level: level,
            reason: sentence(days: days, upcoming: upcoming, followThrough: followThrough),
            daysSinceTogether: days,
            upcomingCount: upcoming
        )
    }

    // MARK: - Words

    private static func sentence(
        days: Int?,
        upcoming: Int,
        followThrough: GroupFollowThrough
    ) -> String {
        var parts: [String] = []

        if let days {
            parts.append("Last got together \(phrase(forDays: days)).")
        } else {
            parts.append("You have not been out yet.")
        }

        if upcoming == 1 {
            parts.append("One plan coming up.")
        } else if upcoming > 1 {
            parts.append("\(upcoming) plans coming up.")
        } else {
            parts.append("Nothing in the diary.")
        }

        // Only when it is known. A percentage over two data points is a rumour.
        if let percentage = followThrough.percentage, percentage < 50 {
            parts.append("Under half of what you agree to happens.")
        }

        return parts.joined(separator: " ")
    }

    private static func phrase(forDays count: Int) -> String {
        switch count {
        case 0: return "today"
        case 1: return "yesterday"
        case 2...13: return "\(count) days ago"
        case 14...20: return "2 weeks ago"
        case 21...29: return "3 weeks ago"
        case 30...59: return "a month ago"
        case 60...364: return "\(count / 30) months ago"
        default: return "over a year ago"
        }
    }
}
