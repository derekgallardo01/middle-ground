import AuthenticationServices
import XCTest
@testable import MiddleGround

/// What a person reads when something fails.
///
/// Nineteen places could put "The operation couldn't be completed. (FIRFirestoreErrorDomain
/// error 7.)" in front of somebody. These pin the translation, and the first one pins the case
/// that is not a translation at all.
final class UserFacingErrorTests: XCTestCase {

    // MARK: - Cancelling is not failing

    func testCancellingSignInWithAppleSaysNothing() {
        let cancelled = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.canceled.rawValue
        )

        XCTAssertTrue(UserFacingError.isCancellation(cancelled))
        XCTAssertNil(
            UserFacingError.message(for: cancelled),
            "choosing not to sign in is not an error and must not raise an alert"
        )
    }

    func testAUserCancelledCocoaErrorAlsoSaysNothing() {
        let cancelled = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)

        XCTAssertTrue(UserFacingError.isCancellation(cancelled))
        XCTAssertNil(UserFacingError.message(for: cancelled))
    }

    func testARealAppleFailureIsStillReported() {
        let failed = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.failed.rawValue
        )

        XCTAssertFalse(UserFacingError.isCancellation(failed))
        XCTAssertNotNil(UserFacingError.message(for: failed))
    }

    // MARK: - Firestore codes people actually hit

    func testPermissionDeniedReadsAsSomethingAPersonCanUnderstand() {
        let denied = NSError(domain: "FIRFirestoreErrorDomain", code: 7)

        let message = UserFacingError.message(for: denied)

        XCTAssertNotNil(message)
        XCTAssertFalse(message!.contains("FIRFirestoreErrorDomain"), "no domain names")
        XCTAssertFalse(message!.contains("7"), "no error codes")
    }

    func testUnavailableTalksAboutTheConnection() {
        for code in [14, 4] {
            let offline = NSError(domain: "FIRFirestoreErrorDomain", code: code)
            XCTAssertEqual(
                UserFacingError.message(for: offline),
                "Couldn't reach the server. Check your connection and try again."
            )
        }
    }

    func testANetworkErrorTalksAboutTheConnectionToo() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)

        XCTAssertEqual(
            UserFacingError.message(for: offline),
            "Couldn't reach the server. Check your connection and try again."
        )
    }

    // MARK: - Not inventing a diagnosis

    func testAnUnknownErrorGetsAPlainSentenceRatherThanAGuess() {
        let mystery = NSError(domain: "SomethingNobodyMapped", code: 99)

        let message = UserFacingError.message(for: mystery)

        XCTAssertEqual(message, "Something went wrong. Please try again.")
        XCTAssertFalse(message!.contains("SomethingNobodyMapped"))
        XCTAssertFalse(message!.contains("99"))
    }

    func testAnUnmappedFirestoreCodeFallsBackRatherThanGuessing() {
        let odd = NSError(domain: "FIRFirestoreErrorDomain", code: 12345)

        XCTAssertEqual(UserFacingError.message(for: odd), "Something went wrong. Please try again.")
    }

    /// The app's own errors already say something considered — those are the good messages and
    /// the translator must not overwrite them.
    func testTheAppsOwnWordingIsKept() {
        XCTAssertEqual(
            UserFacingError.message(for: RelationshipService.PairingError.codeNotFound),
            RelationshipService.PairingError.codeNotFound.errorDescription
        )
        XCTAssertEqual(
            UserFacingError.message(for: RequestError.notAllowedToRespond),
            RequestError.notAllowedToRespond.errorDescription
        )
    }
}
