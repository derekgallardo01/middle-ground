import Factory
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

    // MARK: - Trying a code as both kinds, in order

    /// The sequence itself, which is where the bug actually lived.
    ///
    /// `isWorthTryingAsPlan` has been correct since it was written and onboarding did not call
    /// it — it had its own naive `catch { joinPlan }`. Neither screen's version could be tested,
    /// because neither view model can be built outside an app host (`NotificationService` reaches
    /// for `UNUserNotificationCenter` and the xctest bundle has no bundle proxy). So the sequence
    /// moved here, both screens call it, and this is the test that would have caught it.
    private struct Boom: Error {}

    func testACodeThatNamesAGroupJoinsTheGroupAndNeverAsksAboutPlans() async throws {
        var planWasTried = false

        let outcome = try await JoinCodeFailure.join(
            group: {},
            plan: { planWasTried = true }
        )

        XCTAssertEqual(outcome, .joinedGroup)
        XCTAssertFalse(planWasTried, "a code that worked as a group was still tried as a plan")
    }

    func testACodeThatNamesNoGroupIsTriedAsAPlan() async throws {
        let outcome = try await JoinCodeFailure.join(
            group: { throw RelationshipService.PairingError.codeNotFound },
            plan: {}
        )

        XCTAssertEqual(outcome, .joinedPlan)
    }

    /// The bug, exactly: your own group code. The group lookup *succeeded* and refused the join,
    /// so a plan lookup can only replace a true statement with a false one.
    func testYourOwnCodeIsNotTriedAsAPlanAndSaysSo() async {
        var planWasTried = false

        do {
            _ = try await JoinCodeFailure.join(
                group: { throw RelationshipService.PairingError.ownCode },
                plan: { planWasTried = true }
            )
            XCTFail("joining with your own code reported success")
        } catch {
            XCTAssertEqual(error as? RelationshipService.PairingError, .ownCode)
        }

        XCTAssertFalse(planWasTried, "a code that named a group was answered about a plan")
    }

    func testACodeYouHaveAlreadyUsedSaysThatRatherThanAskingAboutPlans() async {
        do {
            _ = try await JoinCodeFailure.join(
                group: { throw RelationshipService.PairingError.alreadyJoined },
                plan: { XCTFail("should not have been reached") }
            )
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? RelationshipService.PairingError, .alreadyJoined)
        }
    }

    /// Neither kind matched, so the message must not name a kind — the person typing was never
    /// told which they were handed.
    func testACodeThatIsNeitherDoesNotNameAKind() async {
        do {
            _ = try await JoinCodeFailure.join(
                group: { throw RelationshipService.PairingError.codeNotFound },
                plan: { throw RequestError.inviteNotFound }
            )
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? RelationshipService.PairingError, .codeNotFound)
        }
    }

    /// A dropped connection during the group attempt is not a verdict, so the plan attempt still
    /// runs — and may well be the one that works.
    func testANetworkFailureOnTheGroupAttemptStillTriesThePlan() async throws {
        let outcome = try await JoinCodeFailure.join(group: { throw Boom() }, plan: {})

        XCTAssertEqual(outcome, .joinedPlan)
    }
}
