import Foundation

/// Who turns up most, within one group.
///
/// The friendly version of `ReliabilityScore`: the same measurement, shown side by side instead of
/// alone. Everything it displays is already visible to everyone it displays it to — the members of
/// a group can all see whether their shared plans happened — so this aggregates what people
/// already know rather than disclosing anything new. That is the whole justification for showing
/// other people's numbers at all, and it is why the rules below are not negotiable:
///
/// 1. **Never for a couple, and never for two people.** `RelationshipType.seatLimit` already says
///    why: a ranking between two partners is a weapon rather than a signal. The type check alone
///    is not enough — a two-person "friends" group is the same two people with a different label.
/// 2. **Only plans within the group.** A plan someone had with an outsider through a plan invite
///    is none of this group's business, and counting it would let an invisible plan move a
///    visible rank.
/// 3. **No number until there is enough to say one.** `ReliabilityScore.minimumSample` decides
///    that, not this type. Someone with two plans is listed, unranked — being new is not a score.
///
/// **Each member sees a slightly different board, and that is not a bug.** You can only read plans
/// you were part of, so a plan between two other members is invisible to you and cannot count
/// toward their totals here. The alternative — a server-computed global ranking — would mean
/// showing you conclusions drawn from plans you are not allowed to see. The UI says where the
/// numbers come from rather than implying they are absolute.
struct GroupScoreboard: Equatable, Sendable {
    struct Entry: Equatable, Sendable, Identifiable {
        let userID: String
        let displayName: String
        let score: ReliabilityScore
        /// 1-based, and only for entries with enough history. Nil means "listed, not ranked".
        let rank: Int?

        var id: String { userID }
        var percentage: Int? { score.percentage }
    }

    /// Ranked members first, then everyone still building history.
    let entries: [Entry]

    /// Members who have enough settled plans to carry a number.
    var ranked: [Entry] { entries.filter { $0.rank != nil } }
    var unranked: [Entry] { entries.filter { $0.rank == nil } }

    /// A board worth showing has at least two people to compare.
    var isWorthShowing: Bool { ranked.count >= 2 }

    /// Whether this group may ever have a scoreboard.
    ///
    /// Checked on the relationship rather than on the request history, so a couple never gets one
    /// by accident no matter how much history accumulates.
    static func isEligible(_ relationship: Relationship) -> Bool {
        relationship.type != .couple && relationship.participantIDs.count >= 3
    }

    /// Builds the board, or nil when this group may not have one.
    ///
    /// - Parameters:
    ///   - requests: everything the viewer can see. Filtered to this group here rather than by the
    ///     caller, so the "only plans within the group" rule cannot be forgotten at a call site.
    ///   - names: display names by user ID. A member missing a name is still listed — dropping
    ///     them would silently change the ranking.
    static func from(
        relationship: Relationship,
        requests: [Request],
        names: [String: String],
        now: Date = Date()
    ) -> GroupScoreboard? {
        guard isEligible(relationship) else { return nil }

        let members = Set(relationship.participantIDs)
        let groupRequests = requests.filter { request in
            request.allParticipantIDs.count > 1
                && Set(request.allParticipantIDs).isSubset(of: members)
        }

        let scored = relationship.participantIDs.map { userID in
            (
                userID: userID,
                score: ReliabilityScore.from(requests: groupRequests, userID: userID, now: now)
            )
        }

        // Ties keep a stable order by name, so the board does not reshuffle between two people on
        // the same percentage every time the screen is opened.
        let rankable = scored
            .filter { $0.score.percentage != nil }
            .sorted {
                if $0.score.percentage != $1.score.percentage {
                    return ($0.score.percentage ?? 0) > ($1.score.percentage ?? 0)
                }
                return (names[$0.userID] ?? $0.userID) < (names[$1.userID] ?? $1.userID)
            }

        var entries = rankable.enumerated().map { index, item in
            Entry(
                userID: item.userID,
                displayName: names[item.userID] ?? "Someone",
                score: item.score,
                rank: index + 1
            )
        }

        entries += scored
            .filter { $0.score.percentage == nil }
            .sorted { (names[$0.userID] ?? $0.userID) < (names[$1.userID] ?? $1.userID) }
            .map {
                Entry(
                    userID: $0.userID,
                    displayName: names[$0.userID] ?? "Someone",
                    score: $0.score,
                    rank: nil
                )
            }

        return GroupScoreboard(entries: entries)
    }
}
