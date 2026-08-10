import XCTest
@testable import MiddleGround

/// Who brings people in.
///
/// The edge was written on every group join since pairing shipped and read by nothing, so the
/// question a referral loop exists to answer had an answer in the database that nobody could see.
/// These tests are mostly about the ways the number could be *wrong* rather than absent — an
/// attribution that quietly over-counts is worse than none, because it gets acted on.
final class ReferralSummaryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func join(
        by joiner: String,
        invitedBy inviter: String?,
        kind: String = "group",
        daysAgo: Double = 0
    ) -> AnalyticsEvent {
        var metadata = ["kind": kind]
        if let inviter { metadata["invitedBy"] = inviter }
        return AnalyticsEvent(
            userID: joiner,
            type: .inviteRedeemed,
            metadata: metadata,
            at: now.addingTimeInterval(-daysAgo * 86_400)
        )
    }

    func testJoinsAreAttributedToWhoeverSentTheCode() {
        let summary = ReferralSummary.from(events: [
            join(by: "u2", invitedBy: "u1"),
            join(by: "u3", invitedBy: "u1"),
            join(by: "u4", invitedBy: "u9")
        ])

        XCTAssertEqual(summary.inviters.first?.userID, "u1")
        XCTAssertEqual(summary.inviters.first?.joins, 2)
        XCTAssertEqual(summary.totalAttributed, 3)
    }

    /// A plan code admits whoever holds it and records no inviter on purpose
    /// (`RequestService.joinPlan` says why). Counting those would credit people who did nothing.
    func testPlanJoinsAreNotCreditedToAnybody() {
        let summary = ReferralSummary.from(events: [
            join(by: "u2", invitedBy: "u1"),
            join(by: "u5", invitedBy: nil, kind: "plan")
        ])

        XCTAssertEqual(summary.totalAttributed, 1)
        XCTAssertEqual(summary.unattributed, 1)
    }

    /// Group joins written before the edge was kept have no inviter. They must be visible as a
    /// remainder, not silently dropped — a hidden remainder makes the rest look like the whole.
    func testOlderJoinsWithNoEdgeAreCountedAsUnattributed() {
        let summary = ReferralSummary.from(events: [
            join(by: "u2", invitedBy: nil),
            join(by: "u3", invitedBy: "")
        ])

        XCTAssertTrue(summary.inviters.isEmpty)
        XCTAssertEqual(summary.unattributed, 2)
    }

    /// Other events share the collection and must not be counted as joins.
    func testOnlyRedemptionsCount() {
        let noise = AnalyticsEvent(
            userID: "u1",
            type: .inviteShared,
            metadata: ["kind": "group", "invitedBy": "u1"]
        )

        let summary = ReferralSummary.from(events: [noise, join(by: "u2", invitedBy: "u1")])

        XCTAssertEqual(summary.totalAttributed, 1)
        XCTAssertEqual(summary.unattributed, 0)
    }

    /// Ties break by recency so the list does not reshuffle between reads — the same rule the
    /// recipient picker needed for the same reason.
    func testATieIsBrokenByRecencySoTheOrderIsStable() {
        let summary = ReferralSummary.from(events: [
            join(by: "u2", invitedBy: "old", daysAgo: 30),
            join(by: "u3", invitedBy: "recent", daysAgo: 1)
        ])

        XCTAssertEqual(summary.inviters.map(\.userID), ["recent", "old"])
    }

    func testNothingToShowIsNotAnError() {
        let summary = ReferralSummary.from(events: [])

        XCTAssertTrue(summary.inviters.isEmpty)
        XCTAssertEqual(summary.unattributed, 0)
        XCTAssertEqual(summary.totalAttributed, 0)
    }

    /// The window is a fact about the data, not a caveat somebody should have to discover when
    /// the numbers quietly shrink.
    func testTheNinetyDayWindowIsStated() {
        XCTAssertTrue(ReferralSummary(inviters: [], unattributed: 0).windowNote.contains("90 days"))
    }
}
