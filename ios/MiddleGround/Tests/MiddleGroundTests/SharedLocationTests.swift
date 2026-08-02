import XCTest
@testable import MiddleGround

/// The window is the feature. Everything else — the one-shot fix, the deletion, the When In Use
/// permission — follows from location being something you hand over for a few hours around one
/// agreed plan rather than something the app knows about you.
///
/// These mirror `requests/{id}/locations/{userId}` in firestore.rules. If they drift, the app
/// offers a button the backend refuses, or worse, the backend allows something the app promised
/// it would not.
final class SharedLocationTests: XCTestCase {
    private let hour: TimeInterval = 3600

    private func plan(
        status: RequestStatus = .accepted,
        at proposedTime: Date?
    ) -> Request {
        Request(
            creatorID: "alice",
            recipientIDs: ["bob"],
            category: .friends,
            title: "Dinner",
            proposedTime: proposedTime,
            status: status
        )
    }

    func testOpenDuringThePlan() {
        let now = Date()
        XCTAssertTrue(plan(at: now).isWithinLocationWindow(at: now))
    }

    /// "I'm five minutes away" is said on the way, so the window opens before the plan starts.
    func testOpenAnHourBefore() {
        let now = Date()
        XCTAssertTrue(plan(at: now.addingTimeInterval(0.5 * hour)).isWithinLocationWindow(at: now))
    }

    func testShutTwoHoursBefore() {
        let now = Date()
        XCTAssertFalse(plan(at: now.addingTimeInterval(2 * hour)).isWithinLocationWindow(at: now))
    }

    func testOpenThreeHoursAfter() {
        let now = Date()
        XCTAssertTrue(plan(at: now.addingTimeInterval(-3 * hour)).isWithinLocationWindow(at: now))
    }

    func testShutFiveHoursAfter() {
        let now = Date()
        XCTAssertFalse(plan(at: now.addingTimeInterval(-5 * hour)).isWithinLocationWindow(at: now))
    }

    /// Nobody has agreed to anything yet, so there is nothing to be near.
    func testAPlanNobodyAcceptedHasNoWindow() {
        let now = Date()
        XCTAssertFalse(plan(status: .pending, at: now).isWithinLocationWindow(at: now))
    }

    func testACancelledPlanHasNoWindow() {
        let now = Date()
        XCTAssertFalse(plan(status: .cancelled, at: now).isWithinLocationWindow(at: now))
    }

    /// "Split the grocery run" has no moment to be near.
    func testAnUndatedRequestHasNoWindow() {
        XCTAssertFalse(plan(at: nil).isWithinLocationWindow(at: Date()))
    }

    func testOnlyParticipantsCanShare() {
        let now = Date()
        let request = plan(at: now)

        XCTAssertTrue(request.canShareLocation(as: "alice", at: now))
        XCTAssertTrue(request.canShareLocation(as: "bob", at: now))
        XCTAssertFalse(request.canShareLocation(as: "mallory", at: now))
    }

    /// The expiry the client writes has to be the one the rules will accept, or every share is
    /// refused and the failure looks like a permissions bug rather than an arithmetic one.
    func testExpiryMatchesTheEndOfTheWindow() {
        let time = Date()
        XCTAssertEqual(
            plan(at: time).locationExpiry,
            time.addingTimeInterval(Request.locationWindowAfter)
        )
    }

    func testAPointStopsBeingVisibleWhenItLapses() {
        let lapsed = SharedLocation(
            userID: "alice",
            latitude: 0,
            longitude: 0,
            sharedAt: Date().addingTimeInterval(-2 * hour),
            expiresAt: Date().addingTimeInterval(-hour)
        )
        XCTAssertTrue(lapsed.hasExpired)
    }
}
