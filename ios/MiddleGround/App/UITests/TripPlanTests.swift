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
