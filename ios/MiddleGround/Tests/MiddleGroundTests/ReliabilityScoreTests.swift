import XCTest
@testable import MiddleGround

/// Every assertion here is a place the reliability score could quietly become unfair.
final class ReliabilityScoreTests: XCTestCase {
    private func plan(
        _ status: RequestStatus,
        creator: String = "me",
        confirmations: [String: ConfirmationOutcome] = [:],
        proposedTime: Date? = nil,
        updatedAt: Date = Date()
    ) -> Request {
        Request(
            creatorID: creator,
            recipientIDs: creator == "me" ? ["them"] : ["me"],
            category: .daily,
            title: "Plan",
            proposedTime: proposedTime,
            status: status,
            confirmations: confirmations,
            updatedAt: updatedAt
        )
    }

    /// One missed plan is not a pattern, and "0%" beside a single data point is a libel.
    func testNoScoreUntilThereIsEnoughToSay() {
        let requests = [
            plan(.completed, confirmations: ["me": .happened, "them": .happened])
        ]
        let score = ReliabilityScore.from(requests: requests, userID: "me")

        XCTAssertNil(score.percentage)
        XCTAssertFalse(score.hasEnoughData)
    }

    func testAttendedPlansRaiseTheScore() {
        let attended = (0..<5).map { _ in
            plan(.completed, confirmations: ["me": .happened, "them": .happened])
        }
        let score = ReliabilityScore.from(requests: attended, userID: "me")

        XCTAssertEqual(score.attended, 5)
        XCTAssertEqual(score.percentage, 100)
    }

    /// If the two people disagree, the app does not get to pick a winner.
    func testADisputedPlanScoresNothingEitherWay() {
        let disputed = (0..<5).map { _ in
            plan(.accepted, confirmations: ["me": .happened, "them": .didNotHappen])
        }
        let score = ReliabilityScore.from(requests: disputed, userID: "me")

        XCTAssertEqual(score.settledCount, 0, "a contested plan counts for nobody")
        XCTAssertNil(score.percentage)
    }

    /// An unanswered confirmation is not a no-show, or the score punishes people for not
    /// opening an app.
    func testSilenceIsNotAMissedPlan() {
        let unanswered = (0..<5).map { _ in plan(.accepted, confirmations: ["me": .happened]) }
        let score = ReliabilityScore.from(requests: unanswered, userID: "me")

        XCTAssertEqual(score.missed, 0)
        XCTAssertEqual(score.settledCount, 0)
    }

    /// Cancelling a week out is courtesy; an hour before is the thing people mind.
    func testOnlyLateCancellationsCount() {
        let now = Date()
        let early = plan(
            .cancelled,
            proposedTime: now.addingTimeInterval(7 * 24 * 3600),
            updatedAt: now
        )
        let late = plan(
            .cancelled,
            proposedTime: now.addingTimeInterval(3600),
            updatedAt: now
        )

        XCTAssertFalse(early.wasCancelledLate)
        XCTAssertTrue(late.wasCancelledLate)
    }

    func testCancellationStreakBreaksOnAPlanThatWentAhead() {
        let now = Date()
        let requests = [
            plan(.cancelled, updatedAt: now),
            plan(.cancelled, updatedAt: now.addingTimeInterval(-100)),
            plan(.completed,
                 confirmations: ["me": .happened, "them": .happened],
                 updatedAt: now.addingTimeInterval(-200)),
            plan(.cancelled, updatedAt: now.addingTimeInterval(-300))
        ]
        let score = ReliabilityScore.from(requests: requests, userID: "me")

        XCTAssertEqual(score.cancellationStreak, 2, "the run stops at the plan they kept")
        XCTAssertFalse(score.isCancellingRepeatedly)
    }

    /// Somebody else's cancellation says nothing about you.
    func testAnotherPersonsCancellationDoesNotCountAgainstYou() {
        let requests = [plan(.cancelled, creator: "them", proposedTime: Date(), updatedAt: Date())]
        let score = ReliabilityScore.from(requests: requests, userID: "me")

        XCTAssertEqual(score.lateCancellations, 0)
        XCTAssertEqual(score.cancellationStreak, 0)
    }
}
