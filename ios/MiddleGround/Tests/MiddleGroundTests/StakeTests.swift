import XCTest
@testable import MiddleGround

/// The settlement is derived rather than stored, which is what makes it safe: a stored one
/// would have to be writable by whoever confirms attendance, and anyone who can write it
/// can claim it.
final class StakeTests: XCTestCase {
    private func staked(
        _ confirmations: [String: ConfirmationOutcome],
        status: RequestStatus = .accepted,
        accepted: Bool = true
    ) -> Request {
        var request = Request(
            creatorID: "me",
            recipientIDs: ["them"],
            category: .daily,
            title: "Plan",
            proposedTime: Date().addingTimeInterval(-3600),
            status: status,
            confirmations: confirmations
        )
        request.stake = Stake(proposedBy: "me", points: 25, acceptedBy: accepted ? "them" : nil)
        return request
    }

    func testAStakeIsOnlyLiveOnceTheOtherPersonAgrees() {
        let stake = Stake(proposedBy: "me", points: 25)

        XCTAssertFalse(stake.isAccepted)
        XCTAssertFalse(stake.canAccept("me"), "you cannot agree with yourself")
        XCTAssertTrue(stake.canAccept("them"))
    }

    func testAnUnacceptedStakeNeverSettles() {
        let request = staked(["me": .happened, "them": .happened], accepted: false)
        XCTAssertNil(request.stakeSettlement)
        XCTAssertEqual(request.stakeOutcome(for: "me"), 0)
    }

    func testBothTurningUpReturnsTheStakeAsABonus() {
        let request = staked(["me": .happened, "them": .happened], status: .completed)

        XCTAssertEqual(request.stakeSettlement, .kept)
        XCTAssertEqual(request.stakeOutcome(for: "me"), 25)
        XCTAssertEqual(request.stakeOutcome(for: "them"), 25)
    }

    /// Both lose, never one at the other's expense: the record says whether it happened, not
    /// whose fault it was.
    func testAPlanThatDidNotHappenCostsBothSides() {
        let request = staked(["me": .didNotHappen, "them": .didNotHappen])

        XCTAssertEqual(request.stakeSettlement, .forfeited)
        XCTAssertEqual(request.stakeOutcome(for: "me"), -25)
        XCTAssertEqual(request.stakeOutcome(for: "them"), -25)
    }

    func testADisputedPlanSettlesNoStake() {
        let request = staked(["me": .happened, "them": .didNotHappen])
        XCTAssertNil(request.stakeSettlement)
    }

    /// One person cannot collect by answering alone.
    func testOneAnswerSettlesNothing() {
        let request = staked(["me": .happened])
        XCTAssertNil(request.stakeSettlement)
        XCTAssertEqual(request.stakeOutcome(for: "me"), 0)
    }

    func testSomeoneOutsideThePlanGetsNothing() {
        let request = staked(["me": .happened, "them": .happened], status: .completed)
        XCTAssertEqual(request.stakeOutcome(for: "stranger"), 0)
    }
}
