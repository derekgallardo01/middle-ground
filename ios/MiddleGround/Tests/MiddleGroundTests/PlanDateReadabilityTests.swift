import XCTest
@testable import MiddleGround

/// What a card says about when the plan is.
///
/// The composer's `DatePicker` names no `displayedComponents`, so it defaults to date **and
/// time** and people pick 8:00 PM. `dateSummary` then formatted with `time: .omitted`, and the
/// detail screen showed an hour only through `localTimeSummary`, which is gated on the plan being
/// in another zone. So for every domestic plan — which is all of them — the hour was collected and
/// shown on no screen. A card reading "Drinks on Wednesday?" over "August 8, 2026" left the one
/// question worth answering, what time to turn up, findable only inside the negotiation thread.
///
/// Times are pinned to a fixed instant and every case states the zone it reads in, for the reason
/// `PlanTimeZoneTests` gives: a test that passes only in America/Los_Angeles fails in CI.
final class PlanDateReadabilityTests: XCTestCase {

    /// 2026-08-05T19:30:00Z — a Wednesday, and 8:30 PM in Madrid.
    private let instant = Date(timeIntervalSince1970: 1_785_958_200)

    private func plan(zone: String?, nights: Double? = nil) -> Request {
        Request(
            creatorID: "user_1",
            recipientIDs: ["user_2"],
            category: .relationship,
            title: "Drinks on Wednesday?",
            proposedTime: instant,
            endTime: nights.map { instant.addingTimeInterval($0 * 86_400) },
            timeZoneID: zone
        )
    }

    /// Reads a plan the way a reader in a stated zone would, so these do not depend on the
    /// machine running them.
    private func summary(of request: Request, readingIn identifier: String) throws -> String {
        let zone = try XCTUnwrap(TimeZone(identifier: identifier))
        // The plan's own zone wins when set; otherwise the reader's is what renders. Only the
        // second case needs the reader pinned, and `displayTimeZone` reads `TimeZone.current`
        // for it — so those cases state the plan's zone instead, which is equivalent and does
        // not require mutating global state.
        _ = zone
        return try XCTUnwrap(request.dateSummary)
    }

    // MARK: - The hour finally appears

    func testASinglePlanSaysWhatTimeItIs() throws {
        let summary = try summary(of: plan(zone: "Europe/Madrid"), readingIn: "America/Chicago")

        XCTAssertTrue(summary.contains("9:30"), "no time of day in \(summary)")
    }

    func testASinglePlanNamesTheDayOfTheWeek() throws {
        let summary = try summary(of: plan(zone: "Europe/Madrid"), readingIn: "America/Chicago")

        XCTAssertTrue(
            summary.contains("Wed"),
            "a plan titled 'Drinks on Wednesday?' should say Wednesday, got \(summary)"
        )
    }

    /// The weekday and the hour are what changed; the date itself must still be there.
    func testTheDateIsStillThere() throws {
        let summary = try summary(of: plan(zone: "Europe/Madrid"), readingIn: "America/Chicago")

        XCTAssertTrue(summary.contains("5"), "the day of the month is missing from \(summary)")
        XCTAssertTrue(summary.contains("Aug"), "the month is missing from \(summary)")
    }

    // MARK: - A trip is still a range

    /// Nobody asks what o'clock a week in Barcelona starts, and a time on both ends of a range
    /// would make the one line on the card unreadable.
    func testATripReadsAsARangeWithNoTime() throws {
        let summary = try XCTUnwrap(plan(zone: "Europe/Madrid", nights: 4).dateSummary)

        XCTAssertTrue(summary.contains("–"), "a four-night trip rendered as a single date")
        XCTAssertFalse(summary.contains("9:30"), "a range should not carry a time: \(summary)")
    }

    func testATripNamesTheDaysAtBothEnds() throws {
        let summary = try XCTUnwrap(plan(zone: "Europe/Madrid", nights: 4).dateSummary)

        // 5 Aug 2026 is a Wednesday; four nights later is a Sunday.
        XCTAssertTrue(summary.contains("Wed"), "the first day is unnamed in \(summary)")
        XCTAssertTrue(summary.contains("Sun"), "the last day is unnamed in \(summary)")
    }

    // MARK: - Today and tomorrow, on the plan's calendar

    private func plan(at moment: Date, zone: String?) -> Request {
        Request(
            creatorID: "user_1",
            recipientIDs: ["user_2"],
            category: .relationship,
            title: "Coffee",
            proposedTime: moment,
            timeZoneID: zone
        )
    }

    func testTodayIsNamedRatherThanDated() throws {
        let inThreeHours = Date().addingTimeInterval(3 * 3_600)
        // Only meaningful while three hours from now is still today.
        try XCTSkipUnless(Calendar.current.isDateInToday(inThreeHours))

        let summary = try XCTUnwrap(plan(at: inThreeHours, zone: nil).dateSummary)
        XCTAssertTrue(summary.hasPrefix("Today"), "expected Today, got \(summary)")
    }

    func testTomorrowIsNamedRatherThanDated() throws {
        let tomorrow = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 1, to: Date())
        )
        let summary = try XCTUnwrap(plan(at: tomorrow, zone: nil).dateSummary)

        XCTAssertTrue(summary.hasPrefix("Tomorrow"), "expected Tomorrow, got \(summary)")
    }

    /// Past tomorrow it goes back to a weekday and a date. "In 6 days" makes the reader do the
    /// conversion, and the question a plan answers is which evening to keep free.
    func testFurtherOutIsADateNotACountdown() throws {
        let nextWeek = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 6, to: Date())
        )
        let summary = try XCTUnwrap(plan(at: nextWeek, zone: nil).dateSummary)

        XCTAssertFalse(summary.hasPrefix("Today"))
        XCTAssertFalse(summary.hasPrefix("Tomorrow"))
        XCTAssertTrue(summary.contains("·"), "expected a day and an hour, got \(summary)")
    }

    /// The failure the zone field exists to prevent, applied to the word rather than the number.
    /// A plan at 00:30 in Madrid is *tomorrow* there and today to a reader further west; naming
    /// the reader's day is naming a day that is not on the tickets.
    func testTodayIsDecidedOnThePlansCalendarNotTheReaders() throws {
        let madrid = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        var madridCalendar = Calendar.current
        madridCalendar.timeZone = madrid

        // Half past midnight tomorrow, in Madrid.
        let tomorrowThere = try XCTUnwrap(
            madridCalendar.date(
                bySettingHour: 0,
                minute: 30,
                second: 0,
                of: try XCTUnwrap(madridCalendar.date(byAdding: .day, value: 1, to: Date()))
            )
        )
        let summary = try XCTUnwrap(plan(at: tomorrowThere, zone: "Europe/Madrid").dateSummary)

        // Only meaningful when the two clocks actually disagree about the day.
        try XCTSkipIf(madrid.secondsFromGMT(for: tomorrowThere)
                      == TimeZone.current.secondsFromGMT(for: tomorrowThere))
        XCTAssertTrue(
            summary.hasPrefix("Tomorrow"),
            "the plan's own day was not used: \(summary)"
        )
    }

    // MARK: - Unchanged

    func testAPlanWithNoTimeStillHasNothingToSay() {
        var chore = plan(zone: nil)
        chore.proposedTime = nil

        XCTAssertNil(chore.dateSummary)
    }
}
