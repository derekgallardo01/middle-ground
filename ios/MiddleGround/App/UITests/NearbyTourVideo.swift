import XCTest

/// A walkthrough paced for somebody watching it.
///
/// Every other UI test here races: it taps the instant an element exists, because waiting is time
/// nobody gets back. This one holds still, because the artefact is a recording.
///
/// Two things the earlier versions got wrong, both visible in the footage. It re-scrolled before
/// every step, so a minute of the video was the same screen being swiped at; the finder is now
/// brought into frame **once** and left there. And the group half was wrapped in
/// `if waitForExistence`, so when it failed the test still passed and the recording quietly ended
/// on a home screen — everything here asserts.
///
/// Mock mode, so the places, the partner and the group are identical every run.
final class NearbyTourVideo: XCTestCase {
    private var app: XCUIApplication!

    /// Long enough to read a line before it changes, and no longer.
    ///
    /// Was 1.5s, which made a tour of four categories run past two and a half minutes — most of it
    /// a still screen. Reading a chip takes about half a second; the rest was dead air.
    private let beat: TimeInterval = 0.55

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Relaunching is how the group half is reached.
    ///
    /// Driving the recipient picker through its menu lost three takes: the tap landed, the sheet
    /// went away, and the recording showed a bug in the tour rather than the feature. Launching
    /// straight into the state being filmed is both deterministic and shorter to watch.
    private func launch(group: Bool) {
        app = XCUIApplication()
        app.launchArguments = group ? ["-MGMockMode", "-MGComposeGroup"] : ["-MGMockMode"]
        app.launch()
    }

    private func pause(_ multiplier: Double = 1) {
        Thread.sleep(forTimeInterval: beat * multiplier)
    }

    /// The recipient row, matched on a label that starts with "Recipient". A looser predicate
    /// matched a request card in the feed behind the sheet, which is how an earlier recording
    /// dismissed the sheet instead of opening the picker.
    private var recipientPicker: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recipient'")).firstMatch
    }

    private var kindPicker: XCUIElement { app.buttons["Food"] }

    /// Brings a target into frame, once, and stops as soon as it is there.
    ///
    /// The compose sheet is long — quick start, eight category tiles, then the fields — so the
    /// finder begins below the fold. Swiping is what the viewer sees, so it happens as little as
    /// possible.
    @discardableResult
    private func bringIntoFrame(_ element: XCUIElement, tries: Int = 8) -> Bool {
        for _ in 0..<tries {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
        }
        return element.exists && element.isHittable
    }

    private func openCompose() -> Bool {
        guard app.tabBars.firstMatch.waitForExistence(timeout: 40) else { return false }
        pause()
        let compose = app.buttons["Create new request or spontaneous invite"]
        guard compose.waitForExistence(timeout: 10) else { return false }
        compose.tap()
        let newRequest = app.buttons["New Request"]
        if newRequest.waitForExistence(timeout: 5) { newRequest.tap() }
        return app.navigationBars["New Request"].waitForExistence(timeout: 15)
    }

    /// Food, Drinks, Stay, Events. No scrolling between them: the picker and the results sit
    /// together, so once the finder is framed the whole cycle plays without the view moving.
    private func walkThroughEveryKind(_ label: String) {
        // Somewhere only that kind returns. Waiting for `nearbyPlace` to merely *exist* proved
        // nothing: the previous kind's results are still on screen, so the wait returned instantly
        // and the walk passed without the category ever changing. Stay was skipped in an entire
        // recording and this test called it fine.
        let proof = [
            "Food": "Lucia's",
            "Drinks": "The Bell Jar",
            "Stay": "The Rowan Hotel",
            "Events": "The Bell House"
        ]

        for kind in ["Food", "Drinks", "Stay", "Events"] {
            let tab = app.buttons[kind]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(label): no \(kind) tab")
            tab.tap()

            guard let expected = proof[kind] else {
                return XCTFail("\(label): no known result for \(kind)")
            }
            let result = app.staticTexts[expected]
            XCTAssertTrue(
                result.waitForExistence(timeout: 12),
                "\(label): tapped \(kind) and \(expected) never appeared — the category did not change"
            )
            pause(1.2)
            showEveryPlace(in: kind, for: label)
        }
    }

    /// Scrolls the results to the end, so the ones past the edge of the screen are in the film too.
    ///
    /// The row is horizontal and holds more than fits. A recording that never moves it shows the
    /// first two or three and implies that is all there is.
    private func showEveryPlace(in kind: String, for label: String) {
        let chips = app.buttons.matching(identifier: "nearbyPlace")
        let count = chips.count
        XCTAssertGreaterThan(count, 0, "\(label): \(kind) returned nothing to show")

        // The row, not a chip in it. Swiping the first chip scrolls it out of view and every
        // later swipe then fails on an element with an empty frame — which is how this took a
        // recording to notice.
        let row = app.scrollViews["nearbyPlaces"]
        guard row.waitForExistence(timeout: 5) else {
            return XCTFail("\(label): the results row has no handle to scroll")
        }
        for _ in 0..<max(0, count - 2) {
            row.swipeLeft(velocity: .slow)
            pause(0.4)
        }
        pause(0.6)
    }

    /// One half per recipient, filmed the same way, so the two are comparable.
    private func filmCompose(forGroup: Bool) throws {
        launch(group: forGroup)
        let who = forGroup ? "group" : "couple"

        guard openCompose() else {
            return XCTFail("\(who): compose did not open. On screen:\n\(app.debugDescription)")
        }
        pause()

        // Who this plan is for, held on screen long enough to read.
        XCTAssertTrue(bringIntoFrame(recipientPicker), "\(who): no recipient row")
        let label = recipientPicker.label
        if forGroup {
            XCTAssertTrue(
                label.localizedCaseInsensitiveContains("hikers"),
                "the group half is not addressed to the group — it says \(label)"
            )
        }
        pause(1.1)

        let find = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Find somewhere near me'")
        ).firstMatch
        XCTAssertTrue(bringIntoFrame(find), "\(who): no way to search nearby")
        pause()
        find.tap()

        XCTAssertTrue(
            app.buttons["nearbyPlace"].firstMatch.waitForExistence(timeout: 25),
            "\(who): no nearby places came back"
        )
        // Framed once. Everything below plays without the view moving.
        bringIntoFrame(kindPicker)
        pause(2)

        let slider = app.sliders["Search radius"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10), "\(who): no radius control")
        slider.adjust(toNormalizedSliderPosition: 1.0)      // 25 miles
        pause(1.1)
        slider.adjust(toNormalizedSliderPosition: 0.0)      // 1 mile, and the list shortens
        pause(1.1)
        slider.adjust(toNormalizedSliderPosition: 0.25)
        pause()

        walkThroughEveryKind(who)

        // Looking one up properly: the picture, the address, the number, the links out.
        app.buttons["Food"].tap()
        XCTAssertTrue(
            app.staticTexts["Lucia's"].waitForExistence(timeout: 12),
            "\(who): the food results never came back"
        )
        app.buttons["nearbyPlace"].firstMatch.tap()

        let choose = app.buttons["choosePlace"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10), "\(who): the place detail never opened")
        // Held longer than anything else here, because it is the screen with the most on it.
        pause(3.5)
        XCTAssertTrue(
            app.staticTexts["1 Example Street"].exists || app.staticTexts["Address"].exists,
            "\(who): the detail opened without the address it exists to show"
        )

        // Choosing from the detail is what fills in "Where?".
        choose.tap()
        pause(1.6)
        app.terminate()
    }

    /// A couple, then a group. Until today the second was impossible: the picker tagged rows by
    /// "the first participant who is not me", so a couple of [me, Sam] and a group of
    /// [me, Sam, Priya] shared a tag and the group could not be chosen — and a plan sent to it
    /// would have reached Sam alone.
    func testTheTour() throws {
        try filmCompose(forGroup: false)
        try filmCompose(forGroup: true)
    }
}
