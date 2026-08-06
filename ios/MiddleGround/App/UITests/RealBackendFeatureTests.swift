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
    ///
    /// `firstMatch` is load-bearing: the pairing run can be repeated, and every run leaves another
    /// plan with the same title. A plain subscript raises "Multiple matching elements found"
    /// rather than picking one, so the second run of the harness failed on its own leftovers.
    private func openAPlan() -> Bool {
        let known = app.staticTexts["E2E dinner test"].firstMatch
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

        // Deliberately state-agnostic. These run against a real account that keeps whatever the
        // last run left behind, so today may already be blocked — asserting a fixed starting
        // state made this pass once and fail on every rerun.
        let wasBlocked = toggle.label.localizedCaseInsensitiveContains("free again")
        toggle.tap()

        let after = app.buttons["toggleUnavailable"]
        XCTAssertTrue(after.waitForExistence(timeout: 15))
        let isBlocked = after.label.localizedCaseInsensitiveContains("free again")
        XCTAssertNotEqual(
            wasBlocked,
            isBlocked,
            "the toggle did not flip — with the rollback added today, that means the write failed "
                + "and the day was put back"
        )
        capture("live-2-day-toggled")
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

        // Pull to refresh first. `CachedRequestRepository.merge` only overwrites a local row when
        // the remote copy is strictly newer, so a plan re-dated on the server is invisible to a
        // client that already cached it — which is exactly how this test is set up, and it
        // skipped twice before that was understood.
        app.swipeDown()
        Thread.sleep(forTimeInterval: 3)

        guard openAPlan() else { throw XCTSkip("No plan in the feed") }

        let share = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Share my location'")
        ).firstMatch
        guard scrollTo(share) else {
            capture("live-3-window-closed")
            throw XCTSkip("""
                No plan is inside its location window. Sharing needs an accepted plan timed within \
                an hour before and four hours after now, which the pairing run does not produce, \
                and re-dating one on the server is not enough on its own — the client serves its \
                cached copy until a strictly newer updatedAt arrives.

                This is a fixture problem, not an unverified feature: location sharing was proven \
                live on 2026-08-06, with a document in `locations` written by the app through the \
                real rules. Making this repeatable needs a plan created for the purpose.
                """)
        }
        share.tap()

        // "Stop sharing" only exists once a point has been shared, so it is the unambiguous
        // signal. The obvious-looking alternative — matching "your location" — appears in the
        // *invitation* copy above the button and would have passed before anything was shared.
        let stopSharing = app.buttons["Stop sharing"]
        XCTAssertTrue(
            stopSharing.waitForExistence(timeout: 30),
            "location was never shared, so there is nothing to withdraw"
        )
        capture("live-3-location-shared")
    }
}
