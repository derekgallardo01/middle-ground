import XCTest

/// One continuous walk through every screen and feature, photographed as it goes.
///
/// Deliberately a *single* test rather than one per screen. A screen recording of the run is only
/// watchable if the app is never torn down and relaunched mid-way, and each `XCTestCase` method
/// gets a fresh launch — so ten tests would produce ten disjoint clips of an app starting up.
///
/// Ordering is chosen so nothing destroys what a later step needs to photograph:
///
/// - Read-only screens first.
/// - Anything that opens a sheet or an alert is backed out of immediately, because a modal left
///   open silently photographs itself over every screenshot that follows. That has happened here
///   before: four "different" screenshots turned out to be the same stuck sheet, and it was only
///   caught by tiling them into a contact sheet and looking.
/// - Actions that settle a plan (accept, decline) come last, since they remove the response row
///   the earlier frames are meant to show.
final class FullTourUITests: XCTestCase {
    private var app: XCUIApplication!
    private var frame = 0

    override func setUpWithError() throws {
        continueAfterFailure = true   // a missed screen should not end the tour
        app = XCUIApplication()
        app.launchArguments = ["-MGMockMode", "-MGSeedTyping"]
        app.launch()
    }

    // MARK: - Capture

    /// Numbered in capture order, so the filenames sort into the order they were taken and the
    /// contact sheet reads as a walkthrough.
    private func shoot(_ name: String) {
        frame += 1
        settle(0.9)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = String(format: "%02d-%@", frame, name)
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func settle(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func tab(_ name: String) -> XCUIElement { app.tabBars.buttons[name] }

    @discardableResult
    private func open(_ title: String) -> Bool {
        tab("Requests").tap()
        settle(0.6)
        let cell = app.staticTexts[title]
        guard cell.waitForExistence(timeout: 12) else { return false }
        guard bringIntoView(cell) else { return false }
        cell.tap()
        settle(0.8)
        return true
    }

    private func back() {
        let button = app.navigationBars.buttons.firstMatch
        if button.exists && button.isHittable { button.tap() }
        settle(0.6)
    }

    private func scrollTo(_ element: XCUIElement, swipes: Int = 5) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
            settle(0.4)
        }
        return element.exists && element.isHittable
    }

    /// Scrolls an element into reach, in whichever direction it turns out to be.
    ///
    /// Existing is not the same as tappable, and guessing the direction is how the first version
    /// of this silently skipped half the tour: it swiped *down* to reach rows further down the
    /// feed, which scrolls the list the other way.
    @discardableResult
    private func bringIntoView(_ element: XCUIElement, swipes: Int = 6) -> Bool {
        if element.exists && element.isHittable { return true }
        for _ in 0..<swipes {
            app.swipeUp()
            settle(0.3)
            if element.exists && element.isHittable { return true }
        }
        for _ in 0..<(swipes * 2) {
            app.swipeDown()
            settle(0.3)
            if element.exists && element.isHittable { return true }
        }
        return false
    }

    /// Closes a sheet and proves it closed.
    ///
    /// Every stuck-modal failure in this tour has looked the same: the dismissal is attempted, is
    /// not verified, and every later step then taps into a modal while the screenshots carry
    /// perfectly sensible names. A frame called "back at the feed" has been a photograph of the
    /// compose sheet, and of the reschedule picker, on different runs.
    ///
    /// The sheet's own navigation bar is the honest signal — not a button label, which may exist
    /// in several places at once.
    @discardableResult
    private func dismissSheet(titled title: String) -> Bool {
        let bar = app.navigationBars[title]
        for _ in 0..<4 {
            guard bar.exists else { return true }
            if !app.keyboards.allElementsBoundByIndex.isEmpty {
                app.typeText("\n")
                settle(0.3)
            }
            // Matched by prefix, not exact label. Every cancellation button here is given a
            // descriptive accessibility label — "Cancel rescheduling", "Cancel creating request"
            // — which is right for VoiceOver and meant an exact "Cancel" lookup silently found
            // nothing, so the sheet was never dismissed and the swipe-down fallback did not work
            // on a `.large` detent either.
            let cancel = bar.buttons.containing(
                NSPredicate(format: "label BEGINSWITH[c] 'Cancel'")
            ).firstMatch
            if cancel.exists && cancel.isHittable {
                cancel.tap()
            } else {
                app.swipeDown()
            }
            settle(0.9)
        }
        XCTAssertFalse(
            bar.exists,
            "the \(title) sheet would not close, and will photograph itself over everything after this"
        )
        return !bar.exists
    }

    private func text(_ fragment: String) -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", fragment)
        ).firstMatch
    }

    // MARK: - The tour

    /// Split into one method per section: as a single function this ran to a cyclomatic
    /// complexity of 18, which is both a lint failure and a fair description of how hard it
    /// had become to see the order of the tour — the thing that matters most here.
    func testFullTour() throws {
        tourTheFourTabs()
        tourGroupPlan()
        tourStakedPlan()
        tourPlanHappeningNow()
        tourCreatorsOwnPlan()
        tourResponding()
        tourCompose()
    }

    /// The four tabs, untouched.
    private func tourTheFourTabs() {
        // ---- The four tabs, untouched -------------------------------------------------
        tab("Requests").tap()
        shoot("requests-feed")

        tab("Calendar").tap()
        shoot("calendar")

        tab("Activities").tap()
        shoot("activities-progress")
        // Scrolled unconditionally. `bringIntoView` returns true the moment an element is even
        // partly on screen, so asking it to reach a card already peeking at the bottom moved
        // nothing and photographed the same frame twice under two names.
        // Two frames, not three. Swiping past the end of a short screen changes nothing, and the
        // third shot was the second one again under a different name.
        // One scrolled frame. A second was the same picture: the screen ends, so swiping past
        // the bottom changes nothing the camera can see.
        app.swipeUp()
        app.swipeUp()
        shoot("activities-reliability")

        tab("Profile").tap()
        shoot("profile")
        app.swipeUp()
        shoot("profile-groups-and-code")

    }

    /// A group plan: the densest screen in the app.
    private func tourGroupPlan() {
        // ---- A group plan: the densest screen in the app ------------------------------
        if open("Sunday roast?") {
            shoot("group-plan-top")

            _ = scrollTo(text("are in"))
            shoot("group-who-is-in")

            _ = scrollTo(app.buttons.containing(
                NSPredicate(format: "label CONTAINS[c] 'Find a table'")
            ).firstMatch)
            shoot("booking-find-a-table")

            _ = scrollTo(text("Which entrance"))
            shoot("chat-and-threads")

            _ = scrollTo(text("Seen by"))
            shoot("read-receipt-seen-by")

            _ = scrollTo(text("is typing"))
            shoot("typing-indicator")

            // Compose with text in it, so the send button is in its enabled state.
            let field = app.textViews.firstMatch.exists
                ? app.textViews.firstMatch : app.textFields.firstMatch
            if scrollTo(field) {
                field.tap()
                field.typeText("Shall I book it?")
                shoot("composer-with-a-message")
            }
            back()
        }

    }

    /// A staked plan.
    private func tourStakedPlan() {
        // ---- A staked plan -----------------------------------------------------------
        // One frame, not two: the stake row sits above the fold on this plan, so a second
        // "scrolled" shot was the same picture under a different name.
        if open("Climbing on Saturday") {
            shoot("staked-plan-with-points")
            back()
        }

    }

    /// A plan happening now.
    private func tourPlanHappeningNow() {
        // ---- A plan happening now ----------------------------------------------------
        if open("Dinner at Lucia's") {
            shoot("plan-happening-now")
            back()
        }

    }

    /// The creator's own plan.
    private func tourCreatorsOwnPlan() {
        // ---- The creator's own plan --------------------------------------------------
        if open("Date night this Friday?") {
            shoot("creator-waiting")

            // The cancel alert, then straight back out — an alert left open would photograph
            // itself over everything after it.
            let cancel = app.buttons["Cancel request"]
            if bringIntoView(cancel) {
                cancel.tap()
                settle(0.8)
                shoot("cancel-reasons")
                let alert = app.alerts.firstMatch
                if alert.waitForExistence(timeout: 4), alert.buttons["Keep it"].exists {
                    alert.buttons["Keep it"].tap()
                }
                settle(0.6)
            }
            back()
        }

    }

    /// Responding.
    private func tourResponding() {
        // ---- Responding ---------------------------------------------------------------
        //
        // Before compose, not after. Compose is the one modal that has broken this tour
        // repeatedly, and a step that cannot be photographed because an earlier sheet stayed
        // open is worse than a step that runs in a slightly odd order. The feed frame that needs
        // this plan unanswered was taken at the very top of the tour.
        if open("Split the chores this week?") {
            shoot("recipient-can-answer")

            let reschedule = app.buttons.containing(
                NSPredicate(format: "label CONTAINS[c] 'Reschedule'")
            ).firstMatch
            if reschedule.waitForExistence(timeout: 6), bringIntoView(reschedule) {
                reschedule.tap()
                settle(1.0)
                shoot("reschedule-picker")
                dismissSheet(titled: "Reschedule")
            }

            let accept = app.buttons.containing(
                NSPredicate(format: "label CONTAINS[c] 'Accept'")
            ).firstMatch
            if accept.waitForExistence(timeout: 6), bringIntoView(accept) {
                accept.tap()
                settle(1.6)
                shoot("after-accepting")
            }
        }

    }

    /// Compose.
    private func tourCompose() {
        // ---- Compose -----------------------------------------------------------------
        tab("Requests").tap()
        let fab = app.buttons["Create new request or spontaneous invite"]
        if fab.waitForExistence(timeout: 8) {
            fab.tap()
            settle(0.6)
            shoot("compose-menu")
            let newRequest = app.buttons["New Request"]
            if newRequest.waitForExistence(timeout: 4) {
                newRequest.tap()
                settle(1.0)
                shoot("compose-sheet")

                let field = app.textFields.firstMatch
                if field.waitForExistence(timeout: 6) {
                    field.tap()
                    field.typeText("Coffee tomorrow?")
                    shoot("compose-filled")
                }
                dismissSheet(titled: "New Request")
            }
        }

        tab("Requests").tap()
        settle(0.8)
        shoot("back-at-the-feed")

    }

}
