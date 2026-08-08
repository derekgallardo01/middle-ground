import XCTest
@testable import MiddleGround

/// A plan that spans days rather than a moment.
///
/// `proposedTime` has always been the only time a plan had, which is why a trip could not be
/// expressed: "Barcelona, 12–16 May" is a range, not a time. This is the field that makes one
/// possible, and most of these tests are about the plans that are **not** trips — because every
/// plan that exists today has no end, and none of their behaviour may change.
///
/// **Nothing can create a multi-day plan yet.** No screen sets an end, so `endTime` is nil
/// everywhere in production. That is deliberate: the schedulers still ask about attendance four
/// hours after the *start*, the security rules still pin only `proposedTime`, and the location
/// window is still ±hours around a single moment. Until those move, a trip would behave wrongly —
/// so until then, one cannot be made.
final class MultiDayPlanTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func plan(endingAfter days: Double?) -> Request {
        Request(
            creatorID: "user_1",
            recipientIDs: ["user_2"],
            category: .travel,
            title: "Barcelona",
            proposedTime: start,
            endTime: days.map { start.addingTimeInterval($0 * 86_400) }
        )
    }

    // MARK: - Everything that exists today is unchanged

    func testAPlanWithNoEndIsNotATrip() {
        XCTAssertFalse(plan(endingAfter: nil).isMultiDay)
    }

    /// The line that matters most. Attendance is asked four hours after a plan finishes, and for
    /// everything that exists today "finishes" still means `proposedTime`.
    func testAPlanWithNoEndStillEndsWhenItStarts() {
        XCTAssertEqual(plan(endingAfter: nil).effectiveEndTime, start)
    }

    func testAPlanWithNoTimeAtAllIsNotATrip() {
        var chore = plan(endingAfter: nil)
        chore.proposedTime = nil

        XCTAssertFalse(chore.isMultiDay)
        XCTAssertNil(chore.effectiveEndTime)
    }

    // MARK: - A trip

    func testAPlanThatEndsLaterIsATrip() {
        let trip = plan(endingAfter: 4)

        XCTAssertTrue(trip.isMultiDay)
        XCTAssertEqual(trip.effectiveEndTime, start.addingTimeInterval(4 * 86_400))
    }

    /// Asking on the first morning of a five-day holiday whether it happened is asking about
    /// something that is still happening.
    func testATripEndsAtItsEndNotItsStart() {
        XCTAssertNotEqual(plan(endingAfter: 4).effectiveEndTime, start)
    }

    // MARK: - Ends that are not ends

    /// An end before the start is a typo or a bad row, not a range. Treating it as a trip makes
    /// every duration downstream negative.
    func testAnEndBeforeTheStartIsNotATrip() {
        XCTAssertFalse(plan(endingAfter: -2).isMultiDay)
    }

    func testAnEndEqualToTheStartIsNotATrip() {
        XCTAssertFalse(plan(endingAfter: 0).isMultiDay)
    }

    /// And in both cases the plan still behaves exactly like the single-moment plan it is.
    func testABadEndDoesNotMoveWhenThePlanFinishes() {
        XCTAssertEqual(plan(endingAfter: -2).effectiveEndTime, start)
        XCTAssertEqual(plan(endingAfter: 0).effectiveEndTime, start)
    }

    // MARK: - Sharing where you are, on a trip

    private func trip(days: Double) -> Request {
        var request = plan(endingAfter: days)
        request.status = .accepted
        return request
    }

    /// The window used to close four hours into the first morning and stay shut for the rest of
    /// the holiday — a trip being exactly when people most want to find each other.
    func testLocationCanBeSharedOnDayFourOfATrip() {
        let dayFour = start.addingTimeInterval(3.5 * 86_400)

        XCTAssertTrue(trip(days: 5).isWithinLocationWindow(at: dayFour))
    }

    func testTheWindowStillClosesAfterATripEnds() {
        let wellAfter = start.addingTimeInterval(5 * 86_400 + 6 * 3600)

        XCTAssertFalse(trip(days: 5).isWithinLocationWindow(at: wellAfter))
    }

    /// The expiry has to match the pin in `isWellFormed()`, or the server refuses the write and
    /// sharing appears to work while writing nothing.
    func testTheExpiryIsMeasuredFromTheEndOfATrip() throws {
        let expiry = try XCTUnwrap(trip(days: 5).locationExpiry)

        XCTAssertGreaterThan(expiry, start.addingTimeInterval(5 * 86_400))
    }

    /// And none of that may change for the plans that exist today.
    func testASingleMomentPlanKeepsItsOldWindow() {
        var dinner = plan(endingAfter: nil)
        dinner.status = .accepted

        XCTAssertTrue(dinner.isWithinLocationWindow(at: start.addingTimeInterval(3600)))
        XCTAssertFalse(dinner.isWithinLocationWindow(at: start.addingTimeInterval(6 * 3600)))
        XCTAssertEqual(dinner.locationExpiry, start.addingTimeInterval(4 * 3600))
    }

    // MARK: - It has to survive the cache

    /// The repository is remote-then-local, so a field the entity does not persist is invisible
    /// everywhere even when the fetch worked. `name` was lost that way, and `seats` after it.
    func testTheEndSurvivesTheOfflineCache() throws {
        let trip = plan(endingAfter: 4)

        let restored = try XCTUnwrap(RequestEntity(from: trip).toModel())

        XCTAssertEqual(
            restored.endTime?.timeIntervalSince1970 ?? 0,
            trip.endTime?.timeIntervalSince1970 ?? -1,
            accuracy: 1,
            "the cache dropped it, and nothing would have failed"
        )
        XCTAssertTrue(restored.isMultiDay)
    }

    /// `update(from:)` is a separate path from `init(from:)` and has forgotten a field before.
    func testUpdatingACachedPlanKeepsTheEnd() throws {
        let entity = RequestEntity(from: plan(endingAfter: nil))

        entity.update(from: plan(endingAfter: 3))

        XCTAssertTrue(try XCTUnwrap(entity.toModel()).isMultiDay)
    }

    func testAPlanCachedBeforeTripsExistedStillLoads() throws {
        let entity = RequestEntity(from: plan(endingAfter: 3))
        entity.endTime = nil

        let restored = try XCTUnwrap(entity.toModel())

        XCTAssertFalse(restored.isMultiDay)
        XCTAssertEqual(restored.effectiveEndTime, start)
    }
}
