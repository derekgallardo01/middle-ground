import XCTest
@testable import MiddleGround

/// How often a group's plans actually happen — the app's own claim, measured.
///
/// Computed from the group's requests rather than from `plan_outcomes`: those rows carry no user
/// and no request on purpose, which is what lets them outlive a deleted account, and also what
/// makes them unable to answer "how are *we* doing".
final class GroupFollowThroughTests: XCTestCase {
    private let group = Relationship(
        id: "rel_1",
        participantIDs: ["me", "them"],
        type: .couple,
        inviteCode: "MG24KT"
    )

    private func plan(
        id: String,
        status: RequestStatus,
        confirmations: [String: ConfirmationOutcome] = [:],
        agreed: Bool = false,
        participants: [String] = ["them"]
    ) -> Request {
        var request = Request(
            id: id,
            creatorID: "me",
            recipientIDs: participants,
            category: .daily,
            title: "Plan \(id)",
            proposedTime: Date().addingTimeInterval(-3600),
            status: status,
            confirmations: confirmations
        )
        if agreed {
            request.negotiationChain = [
                NegotiationMessage(senderID: "them", responseType: .accept, text: nil)
            ]
        }
        return request
    }

    private func happened(_ id: String) -> Request {
        plan(id: id, status: .completed, confirmations: ["me": .happened, "them": .happened])
    }

    private func fellThrough(_ id: String) -> Request {
        plan(id: id, status: .accepted, confirmations: ["me": .didNotHappen, "them": .didNotHappen])
    }

    // MARK: - Saying nothing until there is something to say

    func testNoFigureUntilThereIsEnoughToSayOne() {
        let rate = GroupFollowThrough.from(
            relationship: group,
            requests: [happened("a"), happened("b")]
        )

        XCTAssertNil(rate.percentage, "a percentage over two plans is a rumour, not a measurement")
        XCTAssertEqual(rate.plansUntilShown, 3)
    }

    func testAFigureAppearsOnceThereIsEnoughHistory() {
        let requests = [happened("a"), happened("b"), happened("c"), happened("d"), fellThrough("e")]

        let rate = GroupFollowThrough.from(relationship: group, requests: requests)

        XCTAssertEqual(rate.happened, 4)
        XCTAssertEqual(rate.fellThrough, 1)
        XCTAssertEqual(rate.percentage, 80)
        XCTAssertEqual(rate.plansUntilShown, 0)
    }

    // MARK: - What counts

    /// Calling off something nobody had agreed to is a plan that never existed, not a broken one.
    func testCancellingSomethingNobodyAgreedToDoesNotCountAgainstTheGroup() {
        let requests = [
            happened("a"), happened("b"), happened("c"), happened("d"), happened("e"),
            plan(id: "f", status: .cancelled, agreed: false)
        ]

        let rate = GroupFollowThrough.from(relationship: group, requests: requests)

        XCTAssertEqual(rate.fellThrough, 0)
        XCTAssertEqual(rate.percentage, 100)
    }

    func testCancellingAnAgreedPlanCountsAsFallingThrough() {
        let requests = [
            happened("a"), happened("b"), happened("c"), happened("d"),
            plan(id: "e", status: .cancelled, agreed: true)
        ]

        let rate = GroupFollowThrough.from(relationship: group, requests: requests)

        XCTAssertEqual(rate.fellThrough, 1)
        XCTAssertEqual(rate.percentage, 80)
    }

    /// The same rule the reliability score uses: if the two people disagree about whether it
    /// happened, the app does not get to pick a winner.
    func testADisputedPlanCountsNeitherWay() {
        let disputed = plan(
            id: "x",
            status: .accepted,
            confirmations: ["me": .happened, "them": .didNotHappen]
        )
        let requests = [happened("a"), happened("b"), happened("c"), happened("d"), disputed]

        let rate = GroupFollowThrough.from(relationship: group, requests: requests)

        XCTAssertEqual(rate.settledCount, 4, "a disagreement is not an outcome")
        XCTAssertNil(rate.percentage)
    }

    func testAnUnansweredPlanIsNotAFailure() {
        let waiting = plan(id: "x", status: .accepted, confirmations: ["me": .happened])
        let requests = [happened("a"), happened("b"), happened("c"), happened("d"), waiting]

        let rate = GroupFollowThrough.from(relationship: group, requests: requests)

        XCTAssertEqual(rate.settledCount, 4, "not having answered yet is not a broken plan")
    }

    // MARK: - Which plans belong to this group

    func testPlansWithPeopleOutsideTheGroupAreIgnored() {
        let elsewhere = plan(
            id: "x",
            status: .completed,
            confirmations: ["me": .happened, "stranger": .happened],
            participants: ["stranger"]
        )

        let rate = GroupFollowThrough.from(relationship: group, requests: [elsewhere])

        XCTAssertEqual(rate.settledCount, 0)
    }

    /// A four-person group where three of you went is the ordinary case, not an edge case.
    func testAPlanWithSomeOfTheGroupStillCounts() {
        let big = Relationship(
            id: "rel_2",
            participantIDs: ["me", "them", "third", "fourth"],
            type: .friends,
            name: "Sunday hikers",
            inviteCode: "MG7QP2"
        )
        let threeOfUs = plan(
            id: "x",
            status: .completed,
            confirmations: ["me": .happened, "them": .happened, "third": .happened],
            participants: ["them", "third"]
        )

        let rate = GroupFollowThrough.from(relationship: big, requests: [threeOfUs])

        XCTAssertEqual(rate.happened, 1)
    }
}
