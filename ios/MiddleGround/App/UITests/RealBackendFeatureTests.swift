import XCTest

/// The features whose real backend path has never once run.
///
/// An audit of production found five collections with **zero documents ever written**: plan chat
/// (`messages`), location sharing (`locations`), shared availability (`availability`), typing
/// presence (`presence`) and read receipts (`reads`). Four of the five have passing UI tests
/// already — in `FeatureCoverageUITests`, under `-MGMockMode`, which substitutes mock
/// repositories and never reaches Firestore or the security rules. The UI was proven; the seam
/// between the app and the backend was not.
///
/// So these run **without** `-MGMockMode`, against real Firebase, and deliberately assert very
/// little about the screen. The evidence that matters is not a green checkmark here — it is the
/// document appearing in Firestore afterwards, and `notifyPlanMessage` finally executing.
/// `Scripts/verify-live-features.mjs` is what actually reads the verdict.
///
/// Runs after `Scripts/two-device-e2e.sh` has paired A and B and left a plan in the feed.
final class RealBackendFeatureTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(asTestUser label: String) {
        // No -MGMockMode: that is the entire point of this file.
        app.launchArguments = ["-MGTestUser", label]
        app.launch()
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, tries: Int = 8) -> Bool {
        for _ in 0..<tries {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// Opens the plan the pairing run left behind, whatever it is called.
    private func openAPlan() -> Bool {
        let known = app.staticTexts["E2E dinner test"]
        if known.waitForExistence(timeout: 30) {
            known.tap()
            return true
        }
        // Fall back to the first card, so a re-run against an existing account still works.
        let anyCard = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] '?'")).firstMatch
        guard anyCard.waitForExistence(timeout: 10) else { return false }
        anyCard.tap()
        return true
    }

    /// Chat, presence and read receipts in one pass — opening a plan and typing in it is what
    /// produces all three, so splitting them into separate runs would only cost a rebuild.
    ///
    /// This is the one that matters most: `notifyPlanMessage` has never executed in production,
    /// because no message has ever existed for it to fire on.
    func testLive1_sendsAPlanMessage() throws {
        launch(asTestUser: "A")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40), "not signed in")

        guard openAPlan() else {
            capture("live-no-plan")
            throw XCTSkip("No plan in the feed — run Scripts/two-device-e2e.sh first")
        }
        capture("live-1-plan-open")

        let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        guard scrollTo(field) else {
            capture("live-1-no-composer")
            return XCTFail("no message composer on the plan. On screen:\n\(app.debugDescription)")
        }
        field.tap()
        // Typing is what writes `presence`; the text is what writes `messages`.
        field.typeText("Live backend check")

        let send = app.buttons["sendMessage"]
        guard send.waitForExistence(timeout: 6), send.isEnabled else {
            capture("live-1-send-unavailable")
            return XCTFail("Send never became available")
        }
        send.tap()

        XCTAssertTrue(
            app.staticTexts["Live backend check"].waitForExistence(timeout: 30),
            "the message never came back from Firestore — the write or the rules refused it"
        )
        capture("live-1-message-sent")
    }

    /// Blocking out a day, which writes to `availability` for every group at once.
    ///
    /// The write path was changed today: it used to swallow every failure with `try?`, so a day
    /// could look blocked on one phone and be shared with nobody. This is the first time that
    /// path runs against real Firestore and real rules.
    func testLive2_marksADayUnavailable() throws {
        launch(asTestUser: "A")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40), "not signed in")

        app.tabBars.buttons["Calendar"].tap()

        let toggle = app.buttons["toggleUnavailable"]
        guard scrollTo(toggle) else {
            capture("live-2-no-toggle")
            return XCTFail("no way to mark yourself unavailable. On screen:\n\(app.debugDescription)")
        }
        XCTAssertTrue(toggle.label.localizedCaseInsensitiveContains("not free"))
        toggle.tap()

        let cleared = app.buttons["toggleUnavailable"]
        XCTAssertTrue(
            cleared.waitForExistence(timeout: 15)
                && cleared.label.localizedCaseInsensitiveContains("free again"),
            "the day did not stay blocked — with the rollback added today, that means the write failed"
        )
        capture("live-2-day-blocked")
    }

    /// Location sharing, the only one of the five with no test of any kind and the only one that
    /// makes a privacy claim to App Review.
    ///
    /// Skips rather than fails when no plan is inside its window: sharing requires an *accepted*
    /// plan timed within an hour before and four hours after now, which a pairing run does not
    /// produce on its own. A skip here is honest — it says the path was not reached, rather than
    /// implying it was checked.
    func testLive3_sharesLocationWhenAPlanIsHappening() throws {
        launch(asTestUser: "A")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40), "not signed in")

        guard openAPlan() else { throw XCTSkip("No plan in the feed") }

        let share = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Share my location'")
        ).firstMatch
        guard scrollTo(share) else {
            capture("live-3-window-closed")
            throw XCTSkip("No plan is inside its location window — needs an accepted plan timed near now")
        }
        share.tap()

        // The permission prompt is a system alert; the simulator is pre-granted by the script.
        let mine = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Sharing' OR label CONTAINS[c] 'your location'")
        ).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 30), "location was never shared")
        capture("live-3-location-shared")
    }
}
