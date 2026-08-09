import Factory
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

    // Without this, anything that builds a view model resolves the real Firestore repositories,
    // Firebase is not configured, and the case dies with "freed pointer was not the last
    // allocation" — a crash rather than a failure, which is why the suite reports zero failures
    // and stops a third of the way through.
    override func setUp() {
        super.setUp()
        AppConfiguration.useMockRepositories = true
        Container.shared.authService.register { MockAuthService() }
    }

    override func tearDown() {
        Container.shared.authService.reset()
        AppConfiguration.useMockRepositories = false
        super.tearDown()
    }

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

    // MARK: - How it reads

    /// A week in Barcelona and a Tuesday dinner must not look identical in a list, which is where
    /// most people see a plan.
    func testATripReadsAsARangeAndADinnerDoesNot() throws {
        let tripDates = try XCTUnwrap(plan(endingAfter: 4).dateSummary)
        let dinnerDates = try XCTUnwrap(plan(endingAfter: nil).dateSummary)

        XCTAssertNotEqual(tripDates, dinnerDates)
        // The end day has to appear. Length was the first assertion here and it was a proxy for
        // this — it failed on a correct range because the single date carried a year and the
        // range did not, which was worth knowing but is not what this test is about.
        XCTAssertTrue(
            tripDates.contains("19"),
            "the end of the trip is missing from \(tripDates)"
        )
        XCTAssertFalse(dinnerDates.contains("19"))
    }

    func testAPlanWithNoTimeHasNothingToShow() {
        var chore = plan(endingAfter: nil)
        chore.proposedTime = nil

        XCTAssertNil(chore.dateSummary)
    }

    /// A backwards end is not a range, and must not render as one.
    func testABackwardsRangeStillReadsAsASingleDate() throws {
        let summary = try XCTUnwrap(plan(endingAfter: -2).dateSummary)

        XCTAssertEqual(summary, try XCTUnwrap(plan(endingAfter: nil).dateSummary))
    }

    func testNightsAreCountedOnlyForATrip() {
        XCTAssertEqual(plan(endingAfter: 5).nightCount, 5)
        XCTAssertNil(plan(endingAfter: nil).nightCount)
        XCTAssertNil(plan(endingAfter: -2).nightCount)
    }

    // MARK: - What a trip must not be offered

    /// Read off a screenshot: a four-night stay in Barcelona offered "check tables at Barcelona
    /// for 3, around the time you agreed". A restaurant booking for a holiday, at a city rather
    /// than a venue, on the first evening of four.
    @MainActor
    func testATripIsNotOfferedARestaurantTable() async {
        let viewModel = RequestDetailViewModel(request: trip(days: 4))
        viewModel.request.location = "Barcelona"

        await viewModel.loadBookingLink()

        XCTAssertNil(viewModel.bookingURL, "a holiday was offered a table for one sitting")
        XCTAssertFalse(viewModel.canBookTable)
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

    // MARK: - Which days a plan occupies

    /// The bug this exists to fix: the calendar asked whether `proposedTime` was the same day, so
    /// a four-night trip appeared on its first day and nowhere else. The middle of a holiday read
    /// as free on the one screen somebody checks to find out whether they are free.
    func testATripOccupiesEveryDayItRuns() {
        let trip = plan(endingAfter: 4)

        for day in 0...4 {
            XCTAssertTrue(
                trip.covers(start.addingTimeInterval(Double(day) * 86_400)),
                "day \(day) of a four-night trip read as free"
            )
        }
    }

    func testATripDoesNotOccupyTheDayBeforeOrAfter() {
        let trip = plan(endingAfter: 4)

        XCTAssertFalse(trip.covers(start.addingTimeInterval(-86_400)))
        XCTAssertFalse(trip.covers(start.addingTimeInterval(5 * 86_400)))
    }

    /// A trip that finishes at breakfast still occupies that morning — somebody is there.
    func testTheLastDayCountsEvenWhenItEndsEarly() {
        var trip = plan(endingAfter: nil)
        trip.endTime = start.addingTimeInterval(3 * 86_400 + 10 * 3600)

        XCTAssertTrue(trip.covers(start.addingTimeInterval(3 * 86_400 + 12 * 3600)))
    }

    /// And a dinner is still exactly one day, which is every plan that exists.
    func testADinnerOccupiesOnlyItsOwnDay() {
        let dinner = plan(endingAfter: nil)

        XCTAssertTrue(dinner.covers(start))
        XCTAssertFalse(dinner.covers(start.addingTimeInterval(86_400)))
        XCTAssertFalse(dinner.covers(start.addingTimeInterval(-86_400)))
    }

    func testAPlanWithNoTimeOccupiesNothing() {
        var chore = plan(endingAfter: nil)
        chore.proposedTime = nil

        XCTAssertFalse(chore.covers(start))
    }

    /// A backwards end is a typo, not a range — it must not swallow the days between.
    func testABackwardsEndOccupiesOnlyTheStartDay() {
        let typo = plan(endingAfter: -2)

        XCTAssertTrue(typo.covers(start))
        XCTAssertFalse(typo.covers(start.addingTimeInterval(-86_400)))
    }

    // MARK: - "Did it happen?" on a holiday you are still on

    /// Read off the same rule three times over: the scheduler was moved to the finish when trips
    /// shipped, the screen was not, and the rules were not either. A five-night holiday asked
    /// whether it happened on its first morning, with four days left to go.
    func testATripIsNotAskedWhetherItHappenedWhileItIsHappening() {
        var running = plan(endingAfter: 5)
        running.status = .accepted
        running.proposedTime = Date().addingTimeInterval(-2 * 86_400)
        running.endTime = Date().addingTimeInterval(3 * 86_400)

        XCTAssertFalse(running.isAwaitingAttendance, "asked mid-holiday whether the holiday happened")
        XCTAssertFalse(running.needsConfirmation(from: "user_1"))
    }

    func testATripIsAskedOnceItHasFinished() {
        var over = plan(endingAfter: 5)
        over.status = .accepted
        over.proposedTime = Date().addingTimeInterval(-6 * 86_400)
        over.endTime = Date().addingTimeInterval(-86_400)

        XCTAssertTrue(over.isAwaitingAttendance)
    }

    /// And a dinner is asked the moment it is over, exactly as before.
    func testADinnerIsStillAskedAssoonAsItPasses() {
        var dinner = plan(endingAfter: nil)
        dinner.status = .accepted
        dinner.proposedTime = Date().addingTimeInterval(-3_600)

        XCTAssertTrue(dinner.isAwaitingAttendance)
    }

    /// A backwards end is a typo, not a range — it must not move the finish earlier and let a
    /// plan be asked about before it has happened.
    func testABackwardsEndDoesNotBringTheQuestionForward() {
        var typo = plan(endingAfter: nil)
        typo.status = .accepted
        typo.proposedTime = Date().addingTimeInterval(86_400)
        typo.endTime = Date().addingTimeInterval(-10 * 86_400)

        XCTAssertFalse(typo.isAwaitingAttendance)
    }

    /// Found by putting a realistic time on a fixture: land at 15:40 on the 4th, fly home at
    /// 11:00 on the 8th, and counting elapsed 24-hour periods gives three — so the card read
    /// "Sep 4 – 8 · 3 nights" directly under its own "Four nights, flights not booked yet."
    /// Nights are what a hotel counts, and a hotel counts dates.
    func testNightsAreCountedByDateNotByElapsedHours() {
        var landing = plan(endingAfter: nil)
        var calendar = Calendar.current
        calendar.timeZone = .current
        let afternoon = calendar.date(bySettingHour: 15, minute: 40, second: 0, of: start) ?? start
        landing.proposedTime = afternoon
        landing.endTime = calendar.date(
            bySettingHour: 11,
            minute: 0,
            second: 0,
            of: afternoon.addingTimeInterval(4 * 86_400)
        )

        XCTAssertEqual(landing.nightCount, 4, "a four-night trip reported a different number")
    }

    /// And a whole number of days still counts the same as it always did.
    func testAnExactNumberOfDaysIsUnchanged() {
        XCTAssertEqual(plan(endingAfter: 5).nightCount, 5)
    }
}
