import XCTest

/// End-to-end walkthrough driven on a real simulator.
///
/// The unit tests cover logic; these cover the things only a launch can prove — that the app
/// starts at all, that navigation works, and that each screen renders real content. The very
/// first version of this app built cleanly and passed 40 unit tests while still crashing
/// before its first frame, which is exactly the gap this closes.
///
/// Runs in mock mode so it is deterministic and needs no backend:
///   xcodebuild -project MiddleGround.xcodeproj -scheme MiddleGroundApp \
///     -destination 'platform=iOS Simulator,name=iPhone 17' test
final class WalkthroughUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MGMockMode"]
        app.launch()
    }

    /// Attaches a screenshot so a failed run shows what the screen actually looked like.
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func tab(_ label: String) -> XCUIElement {
        app.tabBars.buttons[label]
    }

    // MARK: - Launch

    func testAppLaunchesAndReachesMainUI() {
        // The regression that matters most: Firebase used to be touched before
        // FirebaseApp.configure(), aborting the process before any UI existed.
        XCTAssertTrue(
            app.staticTexts["Middle Ground"].waitForExistence(timeout: 20),
            "App did not reach its main UI — check for a launch crash"
        )
        capture("01-launch")
    }

    func testAllFourTabsExist() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        for label in ["Requests", "Calendar", "Activities", "Profile"] {
            XCTAssertTrue(tab(label).exists, "Missing tab: \(label)")
        }
        // The AI tab was removed; it must not come back.
        XCTAssertFalse(tab("AI").exists, "AI tab should have been removed")
        capture("02-tabs")
    }

    // MARK: - Requests

    func testRequestsFeedRendersSeededRequests() {
        XCTAssertTrue(app.staticTexts["Middle Ground"].waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.staticTexts["Weekend Getaway"].waitForExistence(timeout: 10),
            "Seeded request did not render"
        )
        XCTAssertTrue(app.staticTexts["Dinner Tonight?"].exists)
        capture("03-requests")
    }

    func testOpeningARequestShowsItsDetail() {
        XCTAssertTrue(app.staticTexts["Weekend Getaway"].waitForExistence(timeout: 20))
        app.staticTexts["Weekend Getaway"].tap()

        XCTAssertTrue(
            app.staticTexts["Weekend Getaway"].waitForExistence(timeout: 10),
            "Request detail did not open"
        )
        capture("04-request-detail")
    }

    func testComposeSheetOpens() {
        XCTAssertTrue(app.staticTexts["Middle Ground"].waitForExistence(timeout: 20))
        app.buttons["Create new request or spontaneous invite"].tap()
        XCTAssertTrue(app.buttons["New Request"].waitForExistence(timeout: 5))
        app.buttons["New Request"].tap()

        XCTAssertTrue(
            app.navigationBars["New Request"].waitForExistence(timeout: 10),
            "Compose sheet did not open"
        )
        capture("05-compose")
        app.buttons["Cancel creating request"].tap()
    }

    // MARK: - Other tabs

    func testCalendarTabRenders() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        tab("Calendar").tap()
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 10))
        capture("06-calendar")
    }

    func testActivitiesTabShowsGamification() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        tab("Activities").tap()
        XCTAssertTrue(
            app.staticTexts["Achievements"].waitForExistence(timeout: 10),
            "Activities tab did not render its content"
        )
        capture("07-activities")
    }

    func testProfileShowsAccountDeletion() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        tab("Profile").tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 10))

        // App Store Guideline 5.1.1(v): account deletion must be reachable in-app.
        let deleteButton = app.buttons["Delete account"]
        XCTAssertTrue(
            deleteButton.waitForExistence(timeout: 10),
            "Delete Account control is required for App Store review"
        )
        capture("08-profile")

        // Confirm the destructive dialog appears, then back out — this test must not
        // actually delete anything. `.confirmationDialog` presents as an action sheet, so
        // its buttons live under `sheets`, not the app's root button collection.
        deleteButton.tap()

        let alert = app.alerts["Delete your account?"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 5),
            "Deleting an account must be confirmed, not immediate"
        )
        capture("09-delete-confirmation")

        // Both actions must be real, focusable buttons — VoiceOver users have to be able
        // to confirm *and* back out.
        XCTAssertTrue(alert.buttons["Delete Account"].exists, "Destructive action missing")
        let cancel = alert.buttons["Cancel"]
        XCTAssertTrue(cancel.exists, "Confirmation must be cancellable")
        cancel.tap()

        // Still signed in — cancelling must not have deleted anything.
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
    }

    // MARK: - Roles
    //
    // In mock mode the signed-in user is `User.preview` (user_1), who CREATED the seeded
    // requests. So the feed is the creator's view: it must show no response buttons.

    func testCreatorSeesNoResponseButtonsOnTheirOwnRequest() {
        XCTAssertTrue(app.staticTexts["Dinner Tonight?"].waitForExistence(timeout: 20))

        // Accept / Negotiate / Decline belong to the recipient alone.
        for action in ["Accept", "Negotiate", "Decline"] {
            XCTAssertFalse(
                app.buttons[action].exists,
                "A creator must not be able to \(action.lowercased()) their own request"
            )
        }
        capture("11-creator-feed-no-actions")
    }

    func testCreatorSeesWaitingStateAndCanCancel() {
        let pending = app.staticTexts["Date night this Friday?"]
        XCTAssertTrue(pending.waitForExistence(timeout: 20))
        pending.tap()

        // The creator waits; they do not answer.
        let waiting = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Waiting for'")
        ).firstMatch
        XCTAssertTrue(waiting.waitForExistence(timeout: 10), "Creator should see a waiting state")
        capture("12-creator-waiting")

        let cancel = app.buttons["Cancel request"]
        XCTAssertTrue(cancel.exists, "A creator must be able to withdraw their own request")

        // Confirm the destructive alert appears, then back out.
        cancel.tap()
        let alert = app.alerts["Cancel this request?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Cancelling must be confirmed")
        capture("13-cancel-confirmation")
        alert.buttons["Keep it"].tap()
    }

    func testSavingIsNotAvailableToTheCreator() {
        let pending = app.staticTexts["Date night this Friday?"]
        XCTAssertTrue(pending.waitForExistence(timeout: 20))
        pending.tap()

        // The heart used to be ungated entirely — it could flip an accepted request to saved.
        XCTAssertFalse(
            app.buttons["Save for later"].exists,
            "Saving is a response, so it must follow the same role rule"
        )
    }

    // MARK: - Accessibility

    func testLargeTextDoesNotBreakTheFeed() {
        // Dynamic Type was unsupported until the type scale moved to @ScaledMetric; this
        // guards against regressing to fixed-size fonts.
        app.terminate()
        app.launchArguments = ["-MGMockMode", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityL"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Middle Ground"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.tabBars.firstMatch.exists, "Tab bar lost at accessibility text size")
        capture("10-large-text")
    }
}
