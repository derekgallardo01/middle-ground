import XCTest
@testable import MiddleGround

/// What the admin panel says when a section will not load.
///
/// It used to say "This account may not have admin access" for every failure without exception,
/// on the reasoning that a missing claim was the likeliest cause. The first time that guess was
/// wrong it cost real time: the overview was failing because a query wanted a composite index
/// that had not been deployed, and the screen spent the whole search insisting the signed-in
/// admin was not an admin.
///
/// A confident wrong diagnosis is worse than an honest vague one, because it sends the reader
/// somewhere else entirely.
@MainActor
final class AdminLoadFailureTests: XCTestCase {

    private func firestoreError(_ code: Int, _ description: String) -> NSError {
        NSError(
            domain: "FIRFirestoreErrorDomain",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    /// Code 7 is the one case that *is* evidence of a missing claim.
    func testPermissionDeniedStillBlamesAdminAccess() {
        let message = AdminViewModel.loadFailureMessage(
            for: firestoreError(7, "Missing or insufficient permissions.")
        )
        XCTAssertTrue(message.contains("may not have admin access"))
        XCTAssertTrue(message.contains("Missing or insufficient permissions."))
    }

    /// Code 9 is the bug that started this: a query with no index to run on.
    func testAMissingIndexDoesNotGetBlamedOnPermissions() {
        let message = AdminViewModel.loadFailureMessage(
            for: firestoreError(9, "The query requires an index.")
        )
        XCTAssertFalse(
            message.contains("admin access"),
            "a missing index is a deployment fault, not something the reader did"
        )
        XCTAssertTrue(message.contains("index"))
        XCTAssertTrue(message.contains("The query requires an index."))
    }

    /// Anything unrecognised says only what it knows.
    func testAnUnknownFailureDoesNotInventACause() {
        let message = AdminViewModel.loadFailureMessage(
            for: firestoreError(13, "Internal error.")
        )
        XCTAssertFalse(message.contains("admin access"))
        XCTAssertTrue(message.contains("Internal error."))
    }

    /// Offline is offline, whichever screen you are on.
    func testUnavailableReadsAsAConnectionProblem() {
        let message = AdminViewModel.loadFailureMessage(
            for: firestoreError(14, "The service is currently unavailable.")
        )
        XCTAssertTrue(message.contains("connection"))
        XCTAssertFalse(message.contains("admin access"))
    }
}
