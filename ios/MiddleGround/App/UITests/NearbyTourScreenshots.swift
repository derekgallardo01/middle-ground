import XCTest

/// A tour of finding somewhere to go.
///
/// Mock mode, so the places are the same every run and the screenshots do not depend on where the
/// machine happens to be. The real provider is `MKLocalSearch`; this one returns the same four
/// restaurants and the same two hotels every time, which is what makes a tour a tour.
final class NearbyTourScreenshots: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MGMockMode"]
        app.launch()
    }

    /// Brings the finder into frame before photographing it.
    ///
    /// The compose sheet is long — quick-start, eight category tiles, then the fields — so the
    /// nearby row sits well below the fold. The first version of this tour photographed the top of
    /// the sheet four times and called it a tour of a feature none of the frames contained.
    private func scrollToFinder() {
        for _ in 0..<6 where !app.buttons["nearbyPlace"].firstMatch.isHittable {
            app.swipeUp()
        }
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openCompose() -> Bool {
        guard app.tabBars.firstMatch.waitForExistence(timeout: 30) else { return false }
        let compose = app.buttons["Create new request or spontaneous invite"]
        guard compose.waitForExistence(timeout: 10) else { return false }
        compose.tap()
        let newRequest = app.buttons["New Request"]
        if newRequest.waitForExistence(timeout: 5) { newRequest.tap() }
        return app.navigationBars["New Request"].waitForExistence(timeout: 15)
    }

    func testTheTour() throws {
        guard openCompose() else {
            shoot("00-could-not-open-compose")
            return XCTFail("compose did not open. On screen:\n\(app.debugDescription)")
        }

        // 1. Before: the field is empty and nothing has been asked for. No controls, no location.
        for _ in 0..<5 where !app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Find somewhere near me'")
        ).firstMatch.isHittable {
            app.swipeUp()
        }
        shoot("01-before-asking")

        let find = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Find somewhere near me'")
        ).firstMatch
        guard find.waitForExistence(timeout: 10) else {
            shoot("01b-no-find-button")
            return XCTFail("no way to search nearby")
        }
        find.tap()

        // 2. After: results, and the controls that were not there a moment ago.
        let firstResult = app.buttons["nearbyPlace"].firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 20), "no nearby places came back")
        scrollToFinder()
        shoot("02-nearby-results")

        // 3. The radius, at its widest — the full 25 miles that was asked for.
        let slider = app.sliders["Search radius"]
        if slider.waitForExistence(timeout: 5) {
            slider.adjust(toNormalizedSliderPosition: 1.0)
            _ = firstResult.waitForExistence(timeout: 10)
            scrollToFinder()
            shoot("03-radius-25-miles")

            slider.adjust(toNormalizedSliderPosition: 0.0)
            Thread.sleep(forTimeInterval: 1.5)
            scrollToFinder()
            shoot("04-radius-1-mile")
        }

        // 4. A different kind of place.
        let stay = app.buttons["Stay"]
        if stay.waitForExistence(timeout: 5) {
            stay.tap()
            _ = app.buttons["nearbyPlace"].firstMatch.waitForExistence(timeout: 20)
            scrollToFinder()
            shoot("05-hotels")
        }

        // 5. Choosing one fills in "Where?".
        let food = app.buttons["Food"]
        if food.waitForExistence(timeout: 5) { food.tap() }
        let chip = app.buttons["nearbyPlace"].firstMatch
        if chip.waitForExistence(timeout: 20) {
            chip.tap()
            scrollToFinder()
            shoot("06-chosen")
        }
    }
}
