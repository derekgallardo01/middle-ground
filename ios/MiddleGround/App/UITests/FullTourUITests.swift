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
    var app: XCUIApplication!
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
    func shoot(_ name: String) {
        frame += 1
        settle(0.9)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = String(format: "%02d-%@", frame, name)
        shot.lifetime = .keepAlways
        add(shot)
    }

    func settle(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func tab(_ name: String) -> XCUIElement { app.tabBars.buttons[name] }

    @discardableResult
    func open(_ title: String) -> Bool {
        tab("Requests").tap()
        settle(0.6)
        let cell = app.staticTexts[title]
        guard cell.waitForExistence(timeout: 12) else { return false }
        guard bringIntoView(cell) else { return false }
        cell.tap()
        settle(0.8)
        return true
    }

    func back() {
        let button = app.navigationBars.buttons.firstMatch
        if button.exists && button.isHittable { button.tap() }
        settle(0.6)
    }

    func scrollTo(_ element: XCUIElement, swipes: Int = 5) -> Bool {
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
    func bringIntoView(_ element: XCUIElement, swipes: Int = 6) -> Bool {
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
    func dismissSheet(titled title: String) -> Bool {
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

    func text(_ fragment: String) -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", fragment)
        ).firstMatch
    }

    // MARK: - The tour

    /// Split into one method per section: as a single function this ran to a cyclomatic
    /// complexity well past the limit, which is both a lint failure and a fair description of how
    /// hard it had become to see the order of the tour — the thing that matters most here.
    ///
    /// Order is chosen so nothing destroys what a later step needs. Each settling action gets its
    /// own fixture, because accepting and declining cannot both be shown on one plan.
    func testFullTour() throws {
        tourTheFourTabs()
        tourAccept()
        tourDecline()
        tourNegotiate()
        tourCounterWithATime()
        tourConfirmItHappened()
        tourConfirmItDidNot()
        tourStakePoints()
        tourGroupPlanAndChat()
        tourCancelTwoWays()
        tourCalendar()
        tourAvailability()
        tourNewRequest()
        tourSpontaneous()
    }

    /// The four tabs, untouched.
    private func tourTheFourTabs() {
        tab("Requests").tap()
        shoot("feed")

        tab("Calendar").tap()
        shoot("calendar")

        tab("Activities").tap()
        shoot("activities")
        app.swipeUp()
        app.swipeUp()
        shoot("activities-reliability")

        tab("Profile").tap()
        shoot("profile")
        app.swipeUp()
        shoot("profile-groups-and-code")
    }

    /// Accepting a request, and the celebration that follows.
    private func tourAccept() {
        guard open("Pizza on Thursday?") else { return }
        shoot("accept-detail-before")
        if tapResponse("Accept") {
            settle(1.6)
            shoot("accept-confirmed")
            dismissCelebration()
        }
        back()
    }

    /// Declining a request.
    private func tourDecline() {
        guard open("Early gym tomorrow?") else { return }
        shoot("decline-detail-before")
        if tapResponse("Decline") {
            settle(1.4)
            shoot("decline-confirmed")
            dismissCelebration()
        }
        back()
    }

    /// Negotiating — which opens the composer and waits for you to say something.
    ///
    /// The button itself only focuses the field, so a tour that tapped it and moved on filmed an
    /// empty keyboard and no action at all. Typing and sending is what the button is *for*.
    private func tourNegotiate() {
        guard open("Weekend in the mountains?") else { return }
        shoot("negotiate-detail-before")
        guard tapResponse("Negotiate") else { return back() }
        settle(1.0)
        shoot("negotiate-composer-open")

        let field = app.textViews.firstMatch.exists
            ? app.textViews.firstMatch : app.textFields.firstMatch
        if field.waitForExistence(timeout: 4) {
            field.tap()
            field.typeText("Could we make it two nights instead?")
            shoot("negotiate-typed")

            let send = app.buttons["sendMessage"]
            if send.waitForExistence(timeout: 4), send.isEnabled {
                send.tap()
                settle(1.6)
                if !app.keyboards.allElementsBoundByIndex.isEmpty {
                    app.tap()
                    settle(0.6)
                }
                _ = bringIntoView(text("two nights instead"))
                shoot("negotiate-sent-and-showing")
            }
        }
        back()
    }

    /// Countering with a different time, and confirming the plan moved to it.
    private func tourCounterWithATime() {
        guard open("Film night Saturday?") else { return }
        shoot("counter-detail-before")

        // Reschedule is the response that carries a new time.
        if tapResponse("Reschedule") {
            settle(1.2)
            shoot("counter-time-picker")
            let send = app.navigationBars["Reschedule"].buttons.containing(
                NSPredicate(format: "label BEGINSWITH[c] 'Send'")
            ).firstMatch
            if send.exists && send.isHittable {
                send.tap()
                settle(1.6)
                shoot("counter-sent-plan-moved")
                dismissCelebration()
            } else {
                dismissSheet(titled: "Reschedule")
            }
        }
        back()
    }

    /// "Did this happen?" — yes.
    private func tourConfirmItHappened() {
        guard open("Coffee on Monday") else { return }
        _ = bringIntoView(text("Did this happen"))
        shoot("did-it-happen-asked")
        let yes = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Yes, it did'")
        ).firstMatch
        if bringIntoView(yes) {
            yes.tap()
            settle(1.6)
            shoot("confirmed-it-happened")
            dismissCelebration()
        }
        back()
    }

    /// "Did this happen?" — no.
    private func tourConfirmItDidNot() {
        guard open("Market run") else { return }
        _ = bringIntoView(text("Did this happen"))
        let no = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] \"didn't\"")
        ).firstMatch
        if bringIntoView(no) {
            no.tap()
            settle(1.6)
            shoot("confirmed-it-did-not-happen")
            dismissCelebration()
        }
        back()
    }

    /// Putting points on a plan.
    private func tourStakePoints() {
        guard open("Climbing on Saturday") else { return }
        _ = bringIntoView(text("point"))
        shoot("points-on-the-plan")
        back()
    }

    /// The group plan: who is in, booking, conversation, a message actually sent, and seen-by.
    private func tourGroupPlanAndChat() {
        guard open("Sunday roast?") else { return }
        shoot("group-plan")

        _ = bringIntoView(text("are in"))
        shoot("group-who-is-in")

        _ = bringIntoView(app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Find a table'")
        ).firstMatch)
        shoot("booking-find-a-table")

        _ = bringIntoView(text("Which entrance"))
        shoot("chat-with-a-thread")

        _ = bringIntoView(text("Seen by"))
        shoot("seen-by")

        let field = app.textViews.firstMatch.exists
            ? app.textViews.firstMatch : app.textFields.firstMatch
        if bringIntoView(field) {
            field.tap()
            field.typeText("Shall I book it?")
            shoot("message-typed")

            let send = app.buttons["sendMessage"]
            if send.waitForExistence(timeout: 4), send.isEnabled {
                send.tap()
                settle(1.6)
                // Keyboard away first: it covers half the transcript, which is the thing the
                // frame exists to show.
                if !app.keyboards.allElementsBoundByIndex.isEmpty {
                    app.tap()
                    settle(0.6)
                }
                _ = bringIntoView(text("Shall I book it?"))
                shoot("message-sent-and-showing")
            }
        }
        back()
    }

    /// Cancelling, shown with two different reasons on two different plans.
    private func tourCancelTwoWays() {
        cancel(plan: "Date night this Friday?", reason: "Something came up", name: "cancel-something-came-up")
        cancel(plan: "Drinks on Wednesday?", reason: "Our plans changed", name: "cancel-plans-changed")
    }

    private func cancel(plan: String, reason: String, name: String) {
        guard open(plan) else { return }
        let button = app.buttons["Cancel request"]
        if bringIntoView(button) {
            button.tap()
            settle(0.9)
            shoot("\(name)-reasons")
            let alert = app.alerts.firstMatch
            if alert.waitForExistence(timeout: 4), alert.buttons[reason].exists {
                alert.buttons[reason].tap()
                settle(1.4)
                shoot("\(name)-done")
            } else if alert.exists, alert.buttons["Keep it"].exists {
                alert.buttons["Keep it"].tap()
            }
        }
        back()
    }

    /// A plan on the calendar.
    private func tourCalendar() {
        tab("Calendar").tap()
        settle(1.0)
        shoot("calendar-with-plans")
        let entry = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'Lucia'")
        ).firstMatch
        if entry.waitForExistence(timeout: 5), entry.isHittable {
            entry.tap()
            settle(1.0)
            shoot("calendar-plan-detail")
            back()
        }
    }

    /// Marking yourself unavailable, and seeing who else is.
    /// Creating and sending a new request.
    private func tourNewRequest() {
        tab("Requests").tap()
        let fab = app.buttons["Create new request or spontaneous invite"]
        guard fab.waitForExistence(timeout: 8) else { return }
        fab.tap()
        settle(0.7)
        shoot("compose-menu")

        let newRequest = app.buttons["New Request"]
        guard newRequest.waitForExistence(timeout: 4) else { return }
        newRequest.tap()
        settle(1.0)
        shoot("new-request-sheet")

        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 6) {
            field.tap()
            field.typeText("Coffee tomorrow?")
            shoot("new-request-filled")

            let send = app.navigationBars["New Request"].buttons.containing(
                NSPredicate(format: "label BEGINSWITH[c] 'Send'")
            ).firstMatch
            if send.exists && send.isHittable {
                send.tap()
                settle(1.8)
                shoot("new-request-sent")
                dismissCelebration()
            }
        }
        dismissSheet(titled: "New Request")
        tab("Requests").tap()
        settle(0.8)
        shoot("feed-with-the-new-request")
    }

    /// A spontaneous invite, all the way through to it appearing in the feed.
    ///
    /// The first version stopped at the sheet, so the video showed the screen and never which
    /// idea was chosen, how long it lasted, or that anything was sent.
    private func tourSpontaneous() {
        tab("Requests").tap()
        let fab = app.buttons["Create new request or spontaneous invite"]
        guard fab.waitForExistence(timeout: 8) else { return }
        fab.tap()
        settle(0.7)
        let spontaneous = app.buttons["Spontaneous"]
        guard spontaneous.waitForExistence(timeout: 4) else { return }
        spontaneous.tap()
        settle(1.2)
        shoot("spontaneous-sheet")

        // Pick one of the quick ideas, so the recording shows *which* invite is being sent.
        //
        // `matching`, not `containing`: the idea buttons carry an accessibilityLabel, which
        // collapses each one into a single element and hides the Text inside it — and
        // `containing` matches *descendants*, so it found nothing at all. The frame was
        // byte-identical to the one before it, which is how this was caught.
        let idea = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Use idea:'")
        ).firstMatch
        if idea.waitForExistence(timeout: 5), idea.isHittable {
            idea.tap()
            settle(0.9)
            shoot("spontaneous-idea-chosen")
        }

        // Expiry and recipient are both segmented pickers, so their options are segment buttons
        // rather than plain ones. The recipient starts unselected, and Send Now stays disabled
        // until it is chosen — which is why the send silently never happened.
        let hour = app.segmentedControls.buttons["1 hour"].exists
            ? app.segmentedControls.buttons["1 hour"]
            : app.buttons["1 hour"]
        if hour.exists && hour.isHittable {
            hour.tap()
            settle(0.5)
        }
        if app.segmentedControls.count > 1 {
            let recipients = app.segmentedControls.element(boundBy: 1)
            let first = recipients.buttons.element(boundBy: 0)
            if first.exists && first.isHittable {
                first.tap()
                settle(0.5)
            }
        }
        _ = bringIntoView(text("Expires in"))
        shoot("spontaneous-expiry-and-who")

        let send = app.buttons["Send spontaneous request"]
        XCTAssertTrue(bringIntoView(send), "Send Now should be reachable")
        XCTAssertTrue(
            send.isEnabled,
            "Send Now is disabled — an idea and a recipient must both be chosen, and the tour has to choose them"
        )
        send.tap()
        settle(2.2)
        // No frame here: the sheet dismisses itself, so this and the feed shot were identical.
        dismissCelebration()

        dismissAnySheet()

        tab("Requests").tap()
        settle(1.2)
        shoot("feed-with-the-spontaneous-invite")
    }
}
