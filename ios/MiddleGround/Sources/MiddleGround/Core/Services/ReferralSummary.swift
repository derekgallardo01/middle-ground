import Foundation

/// Whose invites actually bring somebody in.
///
/// The edge has been recorded on every group join since pairing shipped —
/// `RelationshipService.join` writes `metadata["invitedBy"]` — and **nothing has ever read it**.
/// Not the admin panel, not a Cloud Function, not the digest. So the one question a referral loop
/// exists to answer, "who is bringing people here", had an answer sitting in the database that
/// nobody could see.
///
/// Computed from events already fetched for the admin Events section, so it costs no extra read.
///
/// **What this is not.** It counts *joins attributed to an inviter*, not people. Somebody who
/// shares one code into a group chat and gets four joins shows as four, which is the truth about
/// the code and not about them. And `events` carries a 90-day TTL, so this is a rolling window,
/// never a lifetime total — said out loud in `windowNote` rather than left for somebody to
/// discover when the numbers quietly shrink.
struct ReferralSummary: Equatable, Sendable {

    struct Inviter: Equatable, Sendable, Identifiable {
        let userID: String
        /// Group joins attributed to this person's code.
        let joins: Int
        /// When the most recent one landed.
        let latest: Date

        var id: String { userID }
    }

    /// Most effective first.
    let inviters: [Inviter]
    /// Joins that carried no `invitedBy` — plan joins, and any group join written before the edge
    /// was recorded. Shown rather than dropped, because a hidden remainder makes the rest look
    /// like the whole.
    let unattributed: Int

    var totalAttributed: Int { inviters.reduce(0) { $0 + $1.joins } }

    var windowNote: String {
        "Events are deleted after 90 days, so this is the last 90 days rather than all time."
    }

    /// Builds it from whatever events the caller already has.
    ///
    /// Only `inviteRedeemed` with `kind == "group"` counts. A plan join deliberately records no
    /// inviter (`RequestService.joinPlan` says why: a plan code admits whoever holds it, and the
    /// creator is not necessarily who passed it on), so counting those would attribute joins to
    /// people who did nothing.
    static func from(events: [AnalyticsEvent]) -> ReferralSummary {
        var joinsByInviter: [String: (count: Int, latest: Date)] = [:]
        var unattributed = 0

        for event in events where event.type == .inviteRedeemed {
            guard event.metadata["kind"] == "group" else {
                unattributed += 1
                continue
            }
            guard let inviter = event.metadata["invitedBy"], !inviter.isEmpty else {
                unattributed += 1
                continue
            }
            let existing = joinsByInviter[inviter]
            joinsByInviter[inviter] = (
                count: (existing?.count ?? 0) + 1,
                latest: max(existing?.latest ?? .distantPast, event.at)
            )
        }

        let inviters = joinsByInviter
            .map { Inviter(userID: $0.key, joins: $0.value.count, latest: $0.value.latest) }
            // Most joins first; ties broken by recency so the order does not shuffle between reads.
            .sorted {
                $0.joins == $1.joins ? $0.latest > $1.latest : $0.joins > $1.joins
            }

        return ReferralSummary(inviters: inviters, unattributed: unattributed)
    }
}
