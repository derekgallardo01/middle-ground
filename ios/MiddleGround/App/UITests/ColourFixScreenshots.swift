import XCTest

/// Photographs the two views whose colours changed, in both schemes.
///
/// The contrast fixes are arithmetic: teal-700 clears 5.47:1 with white, `onLightAccent` clears
/// 6.76:1 on coral. Arithmetic can tell you a ratio passes without telling you whether it looks
/// right, and the last colour bug in this app was caught by a person looking at it rather than by
/// any test — so these exist to be looked at.
///
/// Mock mode on purpose: it seeds a settled plan and a populated streak, which is the only
/// dependable way to reach both views without a backend.
///
/// The colour scheme is set by the *simulator*, not from here — `xcrun simctl ui <udid> appearance
/// dark`. Passing `-AppleInterfaceStyle Dark` as a launch argument looks like it works and does
/// nothing: SwiftUI reads the trait collection, not that default, so the first version of this
/// file captured light mode twice and labelled one of them dark. Run it once per appearance;
/// `Scripts/capture-colours.sh` does that.
final class ColourFixScreenshots: XCTestCase {
    private var app: XCUIApplication!

    /// Whatever appearance the simulator is currently in — see the note above.
    private var scheme: String {
        ProcessInfo.processInfo.environment["MG_SCHEME"] ?? "unknown"
    }

    private func launch() {
        app = XCUIApplication()
        app.launchArguments = ["-MGMockMode"]
        app.launch()
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @discardableResult
    private func bringIntoView(_ element: XCUIElement, tries: Int = 10) -> Bool {
        for _ in 0..<tries {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }

    /// The streak strip: completed days are a coral capsule that used to carry white text.
    func testStreakStrip() {
        launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        app.tabBars.buttons["Activities"].tap()

        let streak = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'streak' OR label CONTAINS[c] 'day'")
        ).firstMatch
        _ = bringIntoView(streak)
        shoot("streak-strip-\(scheme)")
    }

    /// "Did this happen?" — the teal button that was white-on-teal at 2.49:1.
    func testDidThisHappenButton() {
        launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        // The fixture plan that is settled and awaiting a did-it-happen answer.
        let plan = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Coffee' OR label CONTAINS[c] 'roast'")
        ).firstMatch
        guard plan.waitForExistence(timeout: 15) else {
            return shoot("no-settled-plan-\(scheme)")
        }
        plan.tap()

        let prompt = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Did this happen'")
        ).firstMatch
        shoot(bringIntoView(prompt) ? "did-this-happen-\(scheme)" : "plan-detail-\(scheme)")
    }
}
