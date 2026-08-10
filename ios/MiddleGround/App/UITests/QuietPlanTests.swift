import XCTest

/// The three places a quiet plan shows up, driven end to end.
///
/// Unit tests already cover when a plan counts as quiet. What they cannot tell you is whether any
/// of it reaches a screen — and this codebase has shipped several features whose tests passed
/// while the surface rendered nothing. Plan chat, read receipts and shared availability all had
/// zero production documents behind green suites.
///
/// Each test also leaves a screenshot behind, so "it works" is something somebody can look at.
final class QuietPlanTests: XCTestCase {

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

    /// The card has to reach the feed, because the whole problem is that nobody reopens a plan
    /// they have forgotten about.
    func testTheQuietPlanIsOfferedOnTheFeed() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40))

        let card = app.buttons["quietPlanStillOn"]
        XCTAssertTrue(
            card.waitForExistence(timeout: 20),
            "no quiet plan on the feed — check a fixture still reaches that state"
        )

        // And it says why, rather than only that something is wrong.
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] 'Nothing since'")
            ).firstMatch.exists,
            "the card appeared without its reason"
        )
        attach("feed-quiet-plan")
    }

    /// Tapping it records the answer and the card stops asking.
    func testSayingStillOnFromTheFeedIsAcknowledged() {
        let still = app.buttons["quietPlanStillOn"]
        XCTAssertTrue(still.waitForExistence(timeout: 40))
        still.tap()

        // The prompt goes: there is nothing left to say, and an enabled button that re-sends the
        // same answer invites somebody to press it twice and wonder which one counted.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: still)
        waitForExpectations(timeout: 15)
        attach("feed-after-still-on")
    }

    /// Opening the plan shows the same reason and the named answers.
    func testThePlanItselfShowsWhoIsStillIn() {
        XCTAssertTrue(app.buttons["quietPlanStillOn"].waitForExistence(timeout: 40))
        app.buttons["Open it"].tap()

        XCTAssertTrue(
            app.buttons["sayStillOn"].waitForExistence(timeout: 20),
            "the plan opened without the check-in row"
        )
        XCTAssertTrue(app.staticTexts["This has gone quiet"].exists)
        attach("plan-still-on-row")

        app.buttons["sayStillOn"].tap()
        XCTAssertTrue(
            app.staticTexts["You said you're still in"].waitForExistence(timeout: 15),
            "the answer was not reflected back"
        )
        attach("plan-after-still-on")
    }

    /// Every group gets an energy card, and it always carries its sentence.
    ///
    /// It has to be scrolled to: the card sits below the level header, streak, categories and
    /// reliability, and a `LazyVStack` does not build what is off screen, so nothing exists to
    /// wait for until the list has been moved.
    func testTheActivitiesTabShowsGroupEnergy() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40))
        app.tabBars.buttons["Activities"].tap()

        let sentence = app.staticTexts.containing(
            NSPredicate(
                format: "label CONTAINS[c] 'Last got together'"
                    + " OR label CONTAINS[c] 'Nothing to go on yet'"
                    + " OR label CONTAINS[c] 'coming up'"
            )
        ).firstMatch

        XCTAssertTrue(
            sentence.waitForExistence(timeout: 15),
            "an energy card with no sentence is a ring that says you are failing and not at what"
        )

        // Scrolled until it is genuinely on screen, not merely in the tree. XCUITest indexes
        // elements below the fold, so `exists` was already true and the test passed while the
        // screenshot it left behind showed the top of the page — green, and no proof anybody
        // could ever see the card.
        for _ in 0..<10 where !sentence.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(sentence.isHittable, "the energy card never came into view")
        attach("activities-group-energy")
    }
}
