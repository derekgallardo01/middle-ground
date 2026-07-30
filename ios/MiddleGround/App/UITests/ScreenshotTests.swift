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

    private func tab(_ label: String) -> XCUIElement { app.tabBars.buttons[label] }

    private func settle() {
        // Let animation and any async load finish; a screenshot taken mid-transition is
        // rejected by App Store Connect as a partial render often enough to be worth avoiding.
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 20)
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
