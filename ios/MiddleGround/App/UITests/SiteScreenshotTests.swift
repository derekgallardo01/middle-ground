import XCTest

/// Captures the screenshots that go on seekmiddleground.com.
///
/// Separate from `ScreenshotTests`, which produces the App Store set. The two want different
/// images: the store wants five wide shots of the product's centre of gravity, the site wants
/// one tight shot per feature so a changelog entry can show what it is talking about.
///
/// Invoke explicitly — like the store set, this is excluded from a normal test run by naming:
///
///   ./Scripts/site-screenshots.sh
///
/// Everything runs in mock mode against fixtures added for exactly this purpose
/// (`Request.previewStaked`, `.previewHappeningNow`, `.previewGroupPlan`,
/// `Relationship.previewGroup`). Without those, the stake row, the location row and a group of
/// three are unreachable, and the features cannot be shown to anyone who has not installed it.
///
/// ⚠️ These images go stale when the UI moves. Re-run this whenever a screen in it changes — a
/// screenshot showing a design that no longer exists is worse than no screenshot.
final class SiteScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        // Unlike the assertion suites, a failure here should not abandon the run: one screen
        // that moved would otherwise cost every screenshot after it, and the earlier ones are
        // still perfectly usable.
        continueAfterFailure = true
        app = XCUIApplication()
        // The second argument only makes the per-type notification switches visible; iOS never
        // grants push permission to a simulator under test, and without it that feature
        // photographs as a single master switch.
        app.launchArguments = ["-MGMockMode", "-MGShowNotificationSettings"]
        app.launch()
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func settle(_ seconds: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func tab(_ label: String) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[label]
        if inTabBar.waitForExistence(timeout: 5) { return inTabBar }
        return app.buttons[label]
    }

    /// Opens a plan by its title and photographs it, then returns to the feed.
    ///
    /// Scrolling to the named row first: the fixtures that carry the newer features sit below
    /// the fold on a phone, and tapping an element that is off-screen silently does nothing.
    private func shootPlan(titled title: String, as name: String) {
        let row = app.staticTexts[title]
        if !row.waitForExistence(timeout: 5) {
            app.swipeUp()
            settle(0.8)
        }
        guard row.waitForExistence(timeout: 5) else {
            XCTFail("Could not find a plan titled '\(title)' — fixtures may have changed")
            return
        }
        row.tap()
        settle(2.0)
        shoot(name)
        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
            settle(1.0)
        }
    }

    /// Closes the compose sheet, and verifies it actually closed.
    ///
    /// `app.navigationBars.buttons["Cancel"]` matched nothing here — the sheet's Cancel is not
    /// inside a navigation bar — and the miss was silent. The sheet stayed up covering the tab
    /// bar, so the next four screenshots all photographed the compose screen instead of the
    /// screens they were named after. Four identical files is a quiet failure; asserting the
    /// dismissal makes it a loud one.
    private func dismissSheet() {
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 3) {
            cancel.tap()
        } else {
            app.swipeDown()
        }
        settle(1.2)
        if app.buttons["Cancel"].exists {
            app.swipeDown()
            settle(1.2)
        }
        XCTAssertFalse(
            app.buttons["Cancel"].exists,
            "compose sheet would not close — everything after this photographs the wrong screen"
        )
    }

    func testCaptureSiteScreenshots() {
        settle(2.0)

        // 1 — the feed. The hero image, and the only one that has to look busy.
        tab("Requests").tap()
        settle()
        shoot("01-feed")

        // 2 — a plan mid-negotiation, which is the product's actual argument.
        shootPlan(titled: "Dinner Tonight?", as: "02-negotiating")

        // 3 — points staked on a plan happening.
        shootPlan(titled: "Climbing on Saturday", as: "03-stake")

        // 4 — a plan inside its location window, so the sharing row renders.
        shootPlan(titled: "Dinner at Lucia's", as: "04-location")

        // 5 — three people on one plan, one still to answer.
        shootPlan(titled: "Sunday roast?", as: "05-group")

        // 6 — the calendar, where a clash would show.
        tab("Calendar").tap()
        settle()
        shoot("06-calendar")

        // 7 — progress.
        tab("Activities").tap()
        settle()
        shoot("07-progress")

        // 8 — the group list, showing three people in one group.
        tab("Profile").tap()
        settle()
        shoot("08-profile")
        app.swipeUp()
        settle(1.0)
        shoot("09-notifications")

        // 10 — composing, where the suggested places appear. LAST, deliberately.
        //
        // This sheet would not reliably close: neither Cancel nor a swipe dismissed it, and
        // because a capture run continues after a failure, every screen photographed after it
        // was the sheet again. Ordering it last means a sheet that sticks costs exactly one
        // screenshot instead of four.
        //
        // Two steps, not one: the floating button opens a choice between a request and a
        // spontaneous invite. Guessing at a "plus" identifier failed the whole capture — the
        // labels below are the ones WalkthroughUITests already relies on.
        tab("Requests").tap()
        settle()
        let compose = app.buttons["Create new request or spontaneous invite"]
        if compose.waitForExistence(timeout: 5) {
            compose.tap()
            settle(0.8)
            if app.buttons["New Request"].waitForExistence(timeout: 5) {
                app.buttons["New Request"].tap()
                settle(2.0)
                // The place suggestions sit below the title and details fields.
                app.swipeUp()
                settle(1.0)
                shoot("10-compose")
                dismissSheet()
            }
        }
    }
}
