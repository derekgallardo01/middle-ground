import XCTest

/// How `FeatureCoverageUITests` reaches things, split out from the tests themselves.
///
/// That file sat at exactly 500 lines against a 500-line limit, so the next line anybody added to
/// it — a test, or in this case three lines of comment explaining a fix — failed the lint job
/// rather than the thing it was about. Following `FullTourUITests+Helpers`.
///
/// An extension rather than a second class, deliberately: CI names the classes it runs one by one
/// (`-only-testing:MiddleGroundUITests/FeatureCoverageUITests`), so moving *tests* into a new
/// class would drop them from CI silently — which is how `NearbyTourScreenshots` ended up
/// orphaned. Extensions keep the class name, so every test in it still runs.
extension FeatureCoverageUITests {

    func launchApp() {
        app = XCUIApplication()
        app.launchArguments = ["-MGMockMode"] + extraLaunchArguments
        app.launch()
    }

    func tab(_ name: String) -> XCUIElement { app.tabBars.buttons[name] }

    @discardableResult
    func openPlan(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        tab("Requests").tap()
        let cell = app.staticTexts[title]
        guard cell.waitForExistence(timeout: 12) else {
            XCTFail("no plan titled \(title)", file: file, line: line)
            return false
        }
        cell.tap()
        return true
    }

    /// Scrolls until `element` is on screen, or gives up. Most of these rows sit below the fold.
    @discardableResult
    func scrollTo(_ element: XCUIElement, swipes: Int = 5) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }

    func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", fragment)
        ).firstMatch
    }
}
