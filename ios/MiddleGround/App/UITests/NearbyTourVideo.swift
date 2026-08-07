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

    /// Long enough to read a line before it changes.
    private let beat: TimeInterval = 1.5

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
        for kind in ["Food", "Drinks", "Stay", "Events"] {
            let tab = app.buttons[kind]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(label): no \(kind) tab")
            tab.tap()
            // Results, or a line saying there are none. Either is worth holding on.
            _ = app.buttons["nearbyPlace"].firstMatch.waitForExistence(timeout: 12)
            pause(1.8)
        }
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
        pause(1.6)

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
        pause(1.6)
        slider.adjust(toNormalizedSliderPosition: 0.0)      // 1 mile, and the list shortens
        pause(1.6)
        slider.adjust(toNormalizedSliderPosition: 0.25)
        pause()

        walkThroughEveryKind(who)

        // Choosing one fills in "Where?".
        app.buttons["Food"].tap()
        _ = app.buttons["nearbyPlace"].firstMatch.waitForExistence(timeout: 12)
        app.buttons["nearbyPlace"].firstMatch.tap()
        pause(2.2)
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
