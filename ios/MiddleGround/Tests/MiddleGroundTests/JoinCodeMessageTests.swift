import XCTest
@testable import MiddleGround

/// What the join field says when a code doesn't work.
///
/// One field accepts two kinds of code, because the person pasting it was never told which kind
/// they were handed. That is the right design, and it made the failure messages wrong: whatever
/// the *second* attempt said was reported, so a group problem came back as "That invite code
/// doesn't match a plan."
final class JoinCodeMessageTests: XCTestCase {

    // MARK: - Whether the second attempt is worth making

    func testAGroupCodeThatIsAlreadyYoursIsNotTriedAsAPlan() {
        XCTAssertFalse(
            JoinCodeFailure.isWorthTryingAsPlan(afterGroupFailure: RelationshipService.PairingError.alreadyJoined)
        )
        XCTAssertFalse(
            JoinCodeFailure.isWorthTryingAsPlan(afterGroupFailure: RelationshipService.PairingError.ownCode)
        )
    }

    func testACodeThatMatchedNoGroupIsTriedAsAPlan() {
        XCTAssertTrue(
            JoinCodeFailure.isWorthTryingAsPlan(afterGroupFailure: RelationshipService.PairingError.codeNotFound)
        )
    }

    /// A dropped connection is not a verdict on the code, so the plan attempt is still worth one
    /// lookup — it may well be the one that succeeds.
    func testANetworkFailureStillTriesTheOtherKind() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)

        XCTAssertTrue(JoinCodeFailure.isWorthTryingAsPlan(afterGroupFailure: offline))
    }

    // MARK: - What is said when both attempts fail

    func testNeitherKindMatchingDoesNotNameAKind() {
        let message = JoinCodeFailure.message(
            groupFailure: RelationshipService.PairingError.codeNotFound,
            planFailure: RequestError.inviteNotFound
        )

        XCTAssertEqual(message, "We couldn't find that code. Double-check it and try again.")
        XCTAssertNotEqual(
            message,
            RequestError.inviteNotFound.errorDescription,
            "the plan-specific wording answers a question nobody asked"
        )
    }

    /// The code was a plan code, and the plan itself said something specific — that survives.
    func testARealPlanFailureIsReportedAsItself() {
        let message = JoinCodeFailure.message(
            groupFailure: RelationshipService.PairingError.codeNotFound,
            planFailure: RequestError.notAllowedToInvite
        )

        XCTAssertEqual(message, RequestError.notAllowedToInvite.errorDescription)
    }

    func testAnOfflineJoinTalksAboutTheConnection() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)

        let message = JoinCodeFailure.message(groupFailure: offline, planFailure: offline)

        XCTAssertEqual(message, "Couldn't reach the server. Check your connection and try again.")
    }
}
