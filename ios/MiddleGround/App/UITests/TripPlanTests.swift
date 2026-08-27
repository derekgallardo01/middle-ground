import XCTest

/// A plan that spans days, on screen.
///
/// The model, the schedulers and the rules all handle trips now, and none of that proves anybody
/// can see one. This is the check that a range reaches a screen and reads as a range — a week in
/// Barcelona and a Tuesday dinner rendering identically is the failure this feature exists to
/// avoid, and it is invisible to every unit test.
final class TripPlanTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MGMockMode"]
        app.launch()
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Scrolls until the element is genuinely on screen, not merely in the tree.
    ///
    /// `exists` is true for elements below the fold, so a test that waits on it passes while the
    /// screenshot shows the top of the page — which is exactly what happened to the group energy
    /// card before this rule was learned.
    private func scrollTo(_ element: XCUIElement, tries: Int = 10) {
        for _ in 0..<tries where !element.isHittable {
            app.swipeUp()
        }
    }

    /// Flips a toggle by tapping where the switch actually is.
    ///
    /// A `Toggle` in a `Form` is one accessibility element spanning the whole row, so `.tap()`
    /// lands in the middle — on the label — and the value does not change. The test read as
    /// "there is no way to say a plan runs over several days" while the control worked perfectly
    /// for a person. Tapping the trailing edge hits the switch.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    /// Scrolls until the element is built at all.
    ///
    /// A `Form` is a lazy list: a row below the fold does not exist in the tree, so waiting for it
    /// before scrolling waits for something nothing is going to create. The opposite of the
    /// `exists`-is-true-off-screen trap, and easy to conflate with it.
    @discardableResult
    private func scrollUntilItExists(_ element: XCUIElement, tries: Int = 10) -> Bool {
        for _ in 0..<tries where !element.exists {
            app.swipeUp()
        }
        return element.exists
    }

    func testATripShowsItsDatesAsARange() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40))

        let trip = app.staticTexts["Barcelona in May?"]
        XCTAssertTrue(trip.waitForExistence(timeout: 20), "no trip in the feed to look at")
        scrollTo(trip)

        // An en dash is what `.interval` puts between the two dates. Without it the card is
        // showing a single date for something that runs for four nights.
        let range = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '–'")
        ).firstMatch
        XCTAssertTrue(range.exists, "the trip's dates render as a single day")
        attach("feed-trip-range")
    }

    func testOpeningATripShowsHowManyNights() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40))

        let trip = app.staticTexts["Barcelona in May?"]
        XCTAssertTrue(trip.waitForExistence(timeout: 20))
        scrollTo(trip)
        trip.tap()

        let nights = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'night'")
        ).firstMatch
        XCTAssertTrue(nights.waitForExistence(timeout: 15), "a trip opened without saying how long")
        attach("trip-detail")
    }

    /// A trip abroad has to say whose clock its hour is on.
    ///
    /// The model knows and every unit test agrees; none of that puts a word on a screen. If this
    /// row is missing, a plan in Barcelona shows an hour that is simply wrong for everybody
    /// reading it from anywhere else, and nothing anywhere would fail.
    func testATripAbroadNamesItsClock() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40))

        let trip = app.staticTexts["Barcelona in May?"]
        XCTAssertTrue(trip.waitForExistence(timeout: 20))
        scrollTo(trip)
        trip.tap()

        // The zone's generic name, whatever this device localises it to — asserting the exact
        // string would pin the test to one system's ICU data rather than to the behaviour.
        let clock = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'Time' OR label CONTAINS[c] 'GMT'")
        ).firstMatch
        XCTAssertTrue(
            clock.waitForExistence(timeout: 15),
            "a trip abroad showed an hour without saying whose clock it is"
        )
        attach("trip-time-zone")
    }

    /// A trip fills the calendar for as long as it runs.
    ///
    /// The month grid asked whether a plan started on each day, so a four-night trip put one dot on
    /// the calendar and left the other four days looking free — on the one screen somebody checks
    /// to find out whether they are free. The model test proves the rule; only this proves the
    /// grid uses it.
    ///
    /// Counting dots is not enough, and the first version of this test proved it: August already
    /// had seven dotted days from other fixtures, so it passed while the trip sat unexamined in
    /// September. This one reads the trip's own dates off its card, walks to that month, opens a
    /// day in the *middle* of the range, and checks the trip is listed on it.
    func testATripFillsEveryDayItRunsOnTheCalendar() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40))

        let range = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '–'")
        ).firstMatch
        XCTAssertTrue(range.waitForExistence(timeout: 20), "no trip in the feed to follow")
        // "Tue, Sep 22 – Sat, Sep 26" → the first two numbers are the days.
        let numbers = range.label.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap(Int.init)
        let months = Calendar.current.monthSymbols
        guard numbers.count >= 2, let month = months.first(where: {
            range.label.contains($0.prefix(3))
        }) else {
            // A range spanning two months reads differently and this test cannot parse it. Failed
            // out loud rather than passed quietly — the fixture is dated relative to the run.
            return XCTFail("could not read the trip's dates from \"\(range.label)\"")
        }
        // The year is only printed when the plan is not in the current one, so it cannot be read
        // off the label. This required a third number and broke the moment the card stopped
        // spending four characters telling the reader what year it is.
        //
        // Taken from the clock instead, which is where the fixture's own dates come from — it is
        // seeded relative to the run. Wrong only for a trip whose range crosses New Year, which
        // the two-month guard above has already turned away.
        let year = numbers.count >= 3
            ? numbers[2]
            : Calendar.current.component(.year, from: Date())
        let middleDay = (numbers[0] + numbers[1]) / 2
        XCTAssertGreaterThan(numbers[1], numbers[0], "the range is not a range: \(range.label)")

        // Built with the same format style the cell uses, rather than assembled by hand: en-US
        // says "September 6" and the first attempt at this asked for "6 September", which found
        // nothing and read as the feature being broken.
        var parts = DateComponents()
        parts.year = year
        parts.month = (months.firstIndex(of: month) ?? 0) + 1
        parts.day = middleDay
        guard let midDate = Calendar.current.date(from: parts) else {
            return XCTFail("could not build the middle day of \(range.label)")
        }
        let spoken = midDate.formatted(.dateTime.day().month(.wide))

        app.buttons["Calendar"].tap()
        let nextMonth = app.buttons["Next month"]
        XCTAssertTrue(nextMonth.waitForExistence(timeout: 20), "no calendar to look at")

        // If the middle of the trip is unmarked, this cell does not exist and the failure names
        // the day rather than a count.
        let midTrip = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "\(spoken), something planned")
        ).firstMatch
        for _ in 0..<3 where !midTrip.exists {
            nextMonth.tap()
        }
        XCTAssertTrue(
            midTrip.exists,
            "\(spoken) — the middle of the trip — is unmarked on the calendar"
        )

        midTrip.tap()
        attach("calendar-trip-days")
        XCTAssertTrue(
            app.staticTexts["Barcelona in May?"].waitForExistence(timeout: 10),
            "the trip is not listed on a day it runs"
        )
    }

    /// A trip says what is on which day.
    ///
    /// The model groups items into days and the rules let people write them; neither puts a word
    /// on a screen. `invitedBy` was written on every join since pairing shipped and read by
    /// nothing for months — this is the check that the itinerary is not that.
    func testATripShowsItsItineraryByDay() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40))

        let trip = app.staticTexts["Barcelona in May?"]
        XCTAssertTrue(trip.waitForExistence(timeout: 20))
        scrollTo(trip)
        trip.tap()

        let heading = app.staticTexts["Itinerary"]
        XCTAssertTrue(scrollUntilItExists(heading), "a trip opened with no itinerary at all")
        scrollTo(heading)

        // A real item from the fixture, not just the heading — a section that renders its title
        // and none of its contents is exactly what an empty list looks like.
        let dinner = app.staticTexts["Dinner at Bar Cañete"]
        XCTAssertTrue(scrollUntilItExists(dinner), "the itinerary rendered no items")

        // Every day appears, including empty ones: "nothing on Wednesday yet" is information.
        XCTAssertTrue(app.staticTexts["Day 1"].exists)
        XCTAssertTrue(scrollUntilItExists(app.staticTexts["Day 5"]), "the later days are missing")
        attach("trip-itinerary")
    }

    /// And a plan that is not a trip must not grow an empty one.
    func testADinnerHasNoItinerary() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40))

        // Any plan that is not the Barcelona trip.
        let dinner = app.staticTexts["Coffee on Monday"]
        guard dinner.waitForExistence(timeout: 20) else {
            return XCTFail("no single-day plan in the feed to check")
        }
        scrollTo(dinner)
        dinner.tap()

        for _ in 0..<6 where !app.staticTexts["Itinerary"].exists {
            app.swipeUp()
        }
        XCTAssertFalse(
            app.staticTexts["Itinerary"].exists,
            "a one-evening plan was given a day-by-day itinerary"
        )
    }

    /// The compose sheet has to offer the range, or nobody can make one of these.
    func testComposeOffersADateRange() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40))
        app.buttons["Create new request or spontaneous invite"].tap()
        let newRequest = app.buttons["New Request"]
        if newRequest.waitForExistence(timeout: 5) { newRequest.tap() }
        XCTAssertTrue(app.navigationBars["New Request"].waitForExistence(timeout: 20))

        let suggestTime = app.switches["Suggest a time"]
        XCTAssertTrue(scrollUntilItExists(suggestTime), "no time toggle at all")
        scrollTo(suggestTime)

        let before = (suggestTime.value as? String) ?? "unknown"
        flip(suggestTime)
        let after = (suggestTime.value as? String) ?? "unknown"

        // Localises the failure: if no picker appeared, the tap did not take and the missing trip
        // toggle is a symptom rather than the fault. Asked as `datePickers` rather than by label —
        // a DatePicker's title is part of the picker element, not a static text beside it.
        XCTAssertTrue(
            scrollUntilItExists(app.datePickers.firstMatch),
            "no picker after tapping the time toggle. Switch went from \(before) to \(after)."
        )

        let overDays = app.switches["Over several days"]
        XCTAssertTrue(
            scrollUntilItExists(overDays),
            "no way to say a plan runs over several days"
        )
        scrollTo(overDays)
        flip(overDays)

        XCTAssertTrue(app.staticTexts["Ends"].waitForExistence(timeout: 10), "no end to pick")
        attach("compose-date-range")
    }
}
