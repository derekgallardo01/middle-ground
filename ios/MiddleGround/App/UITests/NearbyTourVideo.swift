import XCTest

/// A walkthrough paced for somebody watching it, not for a machine checking it.
///
/// Every other UI test here races: it taps as soon as an element exists, because waiting is time
/// nobody gets back. This one deliberately pauses, because the artefact is a recording and a
/// recording that changes four times a second is unwatchable. `Scripts/record-tour.sh` films the
/// simulator while this drives it.
///
/// Mock mode, so the places, the partner and the group are the same every run — a tour whose
/// content depends on where the machine is standing is not a tour.
final class NearbyTourVideo: XCTestCase {
    private var app: XCUIApplication!

    /// Long enough to read a line before it changes.
    private let beat: TimeInterval = 1.4

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MGMockMode"]
        app.launch()
    }

    private func pause(_ multiplier: Double = 1) {
        Thread.sleep(forTimeInterval: beat * multiplier)
    }

    /// Brings the finder into frame. The compose sheet is long — quick start, eight category
    /// tiles, then the fields — so the nearby row starts well below the fold.
    private func scrollToFinder() {
        for _ in 0..<6 where !app.buttons["nearbyPlace"].firstMatch.isHittable {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    /// The recipient row. Matched on a label that starts with "Recipient" — a looser predicate
    /// matched a request card in the feed behind the sheet, which is how the first recording
    /// dismissed the sheet instead of opening the picker.
    private var recipientPicker: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recipient'")).firstMatch
    }

    private func openCompose() -> Bool {
        guard app.tabBars.firstMatch.waitForExistence(timeout: 30) else { return false }
        pause()
        let compose = app.buttons["Create new request or spontaneous invite"]
        guard compose.waitForExistence(timeout: 10) else { return false }
        compose.tap()
        let newRequest = app.buttons["New Request"]
        if newRequest.waitForExistence(timeout: 5) { newRequest.tap() }
        return app.navigationBars["New Request"].waitForExistence(timeout: 15)
    }

    /// Food, Drinks, Stay, Events — each one searched and left on screen long enough to read.
    private func walkThroughEveryKind() {
        for kind in ["Food", "Drinks", "Stay", "Events"] {
            let tab = app.buttons[kind]
            guard tab.waitForExistence(timeout: 6) else { continue }
            tab.tap()
            _ = app.buttons["nearbyPlace"].firstMatch.waitForExistence(timeout: 15)
            scrollToFinder()
            pause(1.6)
        }
    }

    /// Widens and narrows the radius, so the filtering is visible rather than described.
    private func showTheRadius() {
        let slider = app.sliders["Search radius"]
        guard slider.waitForExistence(timeout: 6) else { return }
        slider.adjust(toNormalizedSliderPosition: 1.0)   // 25 miles
        pause(1.4)
        slider.adjust(toNormalizedSliderPosition: 0.0)   // 1 mile — the list shortens
        pause(1.4)
        slider.adjust(toNormalizedSliderPosition: 0.2)
        pause()
    }

    func testTheTour() throws {
        guard openCompose() else {
            return XCTFail("compose did not open. On screen:\n\(app.debugDescription)")
        }
        pause()

        // ---- Part one: a couple. The recipient the mock data opens on is Sam.
        scrollToFinder()
        let find = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Find somewhere near me'")
        ).firstMatch
        guard find.waitForExistence(timeout: 10) else {
            return XCTFail("no way to search nearby")
        }
        pause()
        find.tap()

        XCTAssertTrue(
            app.buttons["nearbyPlace"].firstMatch.waitForExistence(timeout: 20),
            "no nearby places came back"
        )
        scrollToFinder()
        pause(1.6)

        showTheRadius()
        walkThroughEveryKind()

        // Choosing one fills in "Where?".
        app.buttons["Food"].tap()
        _ = app.buttons["nearbyPlace"].firstMatch.waitForExistence(timeout: 15)
        scrollToFinder()
        app.buttons["nearbyPlace"].firstMatch.tap()
        pause(2)

        // ---- Part two: the same thing for a group.
        //
        // The picker carries both fixtures: Sam, who is a couple, and "Sunday hikers", a group of
        // three. Switching is the point — the feature should not care which it is.
        //
        // Everything here asserts rather than checking `if`. The first version guarded each step,
        // so when the picker selector matched the wrong button and dismissed the sheet, the test
        // passed and the recording quietly ended on a home screen. A tour that cannot fail is not
        // evidence of anything.
        for _ in 0..<8 where !recipientPicker.isHittable {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(
            recipientPicker.waitForExistence(timeout: 10),
            "no recipient picker. On screen:\n\(app.debugDescription)"
        )
        pause()
        recipientPicker.tap()
        pause()

        // The menu is presented above the app, so it is queried from the whole hierarchy rather
        // than from `app.buttons`.
        let group = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'hikers'"))
            .firstMatch
        XCTAssertTrue(
            group.waitForExistence(timeout: 10),
            "the group fixture was not offered. On screen:\n\(app.debugDescription)"
        )
        group.tap()
        pause(1.6)

        // Prove the switch happened before filming the second half.
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'hikers'"))
                .firstMatch.waitForExistence(timeout: 10),
            "the recipient did not change"
        )

        scrollToFinder()
        pause()
        walkThroughEveryKind()

        pause(2)
    }
}
