import XCTest

/// Captures App Store screenshots.
///
/// Separate from `WalkthroughUITests` because the purpose is different: that suite asserts the
/// app works, this one only produces images. It is excluded from the normal test run by naming
/// — invoke it explicitly:
///
///   xcodebuild -project MiddleGround.xcodeproj -scheme MiddleGroundApp \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
///     -only-testing:MiddleGroundUITests/ScreenshotTests test
///
/// Then pull the PNGs out of the .xcresult with `Scripts/screenshots.sh`, which is what
/// actually assembles them for upload.
///
/// Runs in mock mode so the screens are populated and deterministic — `MockRequestRepository`
/// seeds a paired relationship and a request history, which is exactly what a store screenshot
/// needs and what a fresh real account would not have.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MGMockMode"]
        app.launch()
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        // The name is what Scripts/screenshots.sh matches on to order the output.
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Resolves a tab by label across device idioms.
    ///
    /// On iPhone `TabView` renders a bottom tab bar, so `app.tabBars.buttons` finds it. On iPad
    /// it renders as a segmented control in the toolbar and `app.tabBars` matches nothing at
    /// all — the iPad run failed with "No matches found for Descendants matching type TabBar".
    /// Falling back to a plain button lookup covers both.
    private func tab(_ label: String) -> XCUIElement {
        // Tried in order of specificity, each given time to appear rather than probed with
        // `.exists`. A bare `.exists` check races the UI settling and reports false for the
        // real control, which sent this down the wrong branch and failed the tap with
        // "No matches found for Descendants matching type TabBar".
        //
        // `firstMatch` on the final fallback is required, not cosmetic: on Home the label
        // "Requests" also matches the section heading, and an ambiguous query fails the tap
        // outright instead of choosing.
        let candidates = [
            app.tabBars.buttons[label],     // iPhone: bottom tab bar
            app.toolbars.buttons[label],    // iPad: tabs rendered into the toolbar
            app.buttons[label].firstMatch   // anything else
        ]
        for candidate in candidates where candidate.waitForExistence(timeout: 3) {
            return candidate
        }
        return app.buttons[label].firstMatch
    }

    private func settle() {
        // Let animation and any async load finish; a screenshot taken mid-transition is
        // rejected by App Store Connect as a partial render often enough to be worth avoiding.
        if !app.tabBars.firstMatch.waitForExistence(timeout: 10) {
            _ = app.buttons["Requests"].waitForExistence(timeout: 10)
        }
        Thread.sleep(forTimeInterval: 1.5)
    }

    func testCaptureStoreScreenshots() {
        settle()

        // 1 — the feed, which is the product's centre of gravity
        tab("Requests").tap()
        settle()
        shoot("01-requests")

        // 2 — a decision mid-negotiation, which is the actual product.
        //
        // Targeted by title on purpose: tapping the first card lands on "Weekend Getaway",
        // which is already accepted and renders an empty "No responses yet" state — a poor
        // store screenshot. "Dinner Tonight?" carries a negotiation chain.
        let negotiating = app.staticTexts["Dinner Tonight?"]
        if negotiating.waitForExistence(timeout: 5) {
            negotiating.tap()
            Thread.sleep(forTimeInterval: 2.0)
            shoot("02-detail")
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
                Thread.sleep(forTimeInterval: 1.0)
            }
        }

        // 3 — shared plans
        tab("Calendar").tap()
        settle()
        shoot("03-calendar")

        // 4 — streaks and milestones
        tab("Activities").tap()
        settle()
        shoot("04-activities")

        // 5 — pairing and account controls, including Leave and Delete Account
        tab("Profile").tap()
        settle()
        shoot("05-profile")
    }
}
