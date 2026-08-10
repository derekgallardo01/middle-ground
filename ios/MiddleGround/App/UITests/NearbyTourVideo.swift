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

    /// One plan, start to finish, for one kind of place.
    ///
    /// Was two halves that each walked all four categories, which showed the picker working and
    /// never showed a plan being made. Four plans instead — dinner, drinks, a hotel, a gig — each
    /// with its own recipient, its own place chosen from its own search, and its own send.
    ///
    /// Also shorter, despite doing more: the old shape filmed the same eight category taps twice.
    private func filmRequest(_ plan: Plan) throws {
        launch(group: plan.toGroup)

        guard openCompose() else {
            return XCTFail("\(plan.kind): compose did not open. On screen:\n\(app.debugDescription)")
        }
        pause()

        // Who it is for, held long enough to read.
        XCTAssertTrue(bringIntoFrame(recipientPicker), "\(plan.kind): no recipient row")
        let recipient = recipientPicker.label
        XCTAssertTrue(
            recipient.localizedCaseInsensitiveContains(plan.recipient),
            "\(plan.kind): addressed to \(recipient), expected \(plan.recipient)"
        )
        // And what kind of plan it is, which follows from who it is for. Asserted rather than
        // left to the eye: this opened as "Relationship" for everybody, group plans included,
        // and it took watching a recording to notice.
        let expectedType = plan.toGroup ? "Friends" : "Relationship"
        let chosenType = app.buttons[expectedType]
        if chosenType.waitForExistence(timeout: 5) {
            XCTAssertTrue(
                chosenType.isSelected,
                "\(plan.kind) to \(plan.recipient): \(expectedType) is not the selected kind"
            )
        }
        pause(1.1)

        // What it is about, typed before the place so the sheet reads as a plan being written.
        let title = app.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "\(plan.kind): no title field")
        title.tap()
        title.typeText(plan.title)
        pause(0.8)

        let find = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Find somewhere near me'")
        ).firstMatch
        XCTAssertTrue(bringIntoFrame(find), "\(plan.kind): no way to search nearby")
        pause(0.6)
        find.tap()

        XCTAssertTrue(
            app.buttons["nearbyPlace"].firstMatch.waitForExistence(timeout: 25),
            "\(plan.kind): no nearby places came back"
        )
        // Framed once. Everything below plays without the view moving.
        bringIntoFrame(kindPicker)
        pause(1.2)

        // The kind this plan is about.
        //
        // Proved by the results changing, not by a name. Naming the place the search must return
        // only worked while the places were invented; against real ones it would assert that a
        // particular restaurant still trades. What matters is that tapping the category changed
        // what came back — and merely waiting for "a result" proved nothing, because the previous
        // category's results are still on screen and satisfy it instantly.
        let before = app.buttons.matching(identifier: "nearbyPlace").firstMatch.label
        let tab = app.buttons[plan.kind]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "no \(plan.kind) tab")
        tab.tap()

        if plan.changesCategory {
            XCTAssertTrue(
                waitForResults(toChangeFrom: before),
                "\(plan.kind): the results still say '\(before)' — the category did not change"
            )
        } else {
            XCTAssertTrue(
                app.buttons["nearbyPlace"].firstMatch.waitForExistence(timeout: 12),
                "\(plan.kind): nothing came back"
            )
        }
        pause(1.0)

        // How far, and what that does to the list.
        let slider = app.sliders["Search radius"]
        if slider.waitForExistence(timeout: 5) {
            slider.adjust(toNormalizedSliderPosition: 1.0)      // 25 miles
            pause(0.9)
            slider.adjust(toNormalizedSliderPosition: 0.35)
            pause(0.9)
        }

        showEveryPlace(in: plan.kind, for: plan.kind)

        // The place itself: the picture, the address, the number, the links out.
        let chip = app.buttons.matching(identifier: "nearbyPlace").firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "\(plan.kind): nothing left to open")
        chip.tap()

        let choose = app.buttons["choosePlace"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10), "\(plan.kind): the detail never opened")
        // The longest hold in the tour: it is the screen with the most on it, and the picture
        // takes a moment to arrive from Apple.
        pause(4.5)
        choose.tap()
        pause(1.2)

        // And sent, which is the point of all of it.
        let send = app.buttons["Send"]
        if send.waitForExistence(timeout: 5), send.isEnabled {
            send.tap()
            pause(2.0)
        }
        app.terminate()
    }

    /// Waits for the first result to become a different place.
    private func waitForResults(toChangeFrom previous: String, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let now = app.buttons.matching(identifier: "nearbyPlace").firstMatch.label
            if !now.isEmpty && now != previous { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// What each of the four plans is.
    private struct Plan {
        let kind: String
        let title: String
        let toGroup: Bool
        var recipient: String { toGroup ? "hikers" : "Sam" }
        /// Compose opens on Food, so only the other three can prove themselves by the list
        /// changing. Asserting a change for Food would fail on a tour that is working.
        var changesCategory: Bool { kind != "Food" }
    }

    /// Every kind of place, to each kind of recipient: eight plans, in four adjacent pairs.
    ///
    /// Was four, one kind each, with two going to a person and two to a group — which showed each
    /// kind once and never let the two audiences be compared on the same kind. The pairs are
    /// adjacent on purpose: dinner-for-two is followed immediately by dinner-for-the-group, so the
    /// only thing that differs between them is the thing being demonstrated.
    ///
    /// The recording is split back into these eight clips afterwards, on the home screen each one
    /// ends on — see `Scripts/record-tour.sh`, where the names below are repeated. Their order is
    /// what pairs a clip with its name, so this list and that one have to stay in step.
    func testTheTour() throws {
        // A plan filmed to be thrown away.
        //
        // Launching the app before recording was not enough: the first plan of a run still lost
        // most of its frames — 13 seconds of video for 70 seconds of work, against 72 to 78 for
        // every plan after it. Whatever the first one pays for (the first search, the first
        // snapshot, the first sheet) it pays once, so it pays here instead of inside the footage.
        // `Scripts/record-tour.sh` drops the segment this produces.
        try filmRequest(Plan(kind: "Food", title: "Warm-up", toGroup: false))

        let plans = [
            Plan(kind: "Food", title: "Dinner Friday?", toGroup: false),
            Plan(kind: "Food", title: "Dinner, all of us?", toGroup: true),
            Plan(kind: "Drinks", title: "Drinks after work?", toGroup: false),
            Plan(kind: "Drinks", title: "Drinks, everyone?", toGroup: true),
            Plan(kind: "Stay", title: "Weekend away?", toGroup: false),
            Plan(kind: "Stay", title: "Weekend away, all of us?", toGroup: true),
            Plan(kind: "Events", title: "Gig on Saturday?", toGroup: false),
            Plan(kind: "Events", title: "Gig on Saturday, everyone?", toGroup: true)
        ]

        for plan in plans {
            try filmRequest(plan)
        }
    }
}
