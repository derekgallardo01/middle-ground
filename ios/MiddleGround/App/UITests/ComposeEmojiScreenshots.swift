import XCTest

/// Looks at the compose sheet's emoji picker, which nothing else captures.
///
/// A capture suite exists because this codebase has repeatedly shipped features whose tests were
/// green and whose screens rendered nothing — the group energy card among them. The picker is a
/// new control on a screen behind a sheet, so it is exactly the shape of thing that passes its
/// unit tests while being invisible, cut off, or unreadable in practice.
///
/// Run with `MG_SHOT_CLASS=ComposeEmojiScreenshots ./Scripts/screenshots.sh /tmp/compose-shots`.
final class ComposeEmojiScreenshots: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
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

    func testCaptureTheEmojiPicker() throws {
        XCTAssertTrue(
            app.buttons["Create new request or spontaneous invite"].waitForExistence(timeout: 20)
        )
        app.buttons["Create new request or spontaneous invite"].tap()

        // The FAB is a menu, so the sheet is two taps away.
        let newRequest = app.buttons["New Request"]
        XCTAssertTrue(newRequest.waitForExistence(timeout: 5))
        newRequest.tap()

        XCTAssertTrue(app.textFields["Where? (optional)"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)
        shoot("01-compose-with-picker")

        // The picker has to actually be reachable, not merely present: a row below the fold in a
        // `Form` does not exist at all, which is how a control can pass every unit test and be
        // untappable. `exists` alone would not catch that.
        let icons = app.buttons.matching(identifier: "Plan icon")
        XCTAssertGreaterThan(icons.count, 1, "the picker offered fewer than two faces")

        // Choosing one is the whole point, so prove a tap lands rather than only that it renders.
        let second = icons.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.tap()
        Thread.sleep(forTimeInterval: 0.6)
        shoot("02-picker-after-choosing")
    }
}
