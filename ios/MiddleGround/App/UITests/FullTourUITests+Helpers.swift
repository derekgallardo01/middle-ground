import XCTest

/// Driving helpers for the recorded tour.
///
/// Split out because the tour crossed the 500-line limit once it covered every action. The tour
/// itself should read as a list of what is being filmed; how each control is found is a separate
/// concern, and most of it is hard-won — see the notes on each one.
extension FullTourUITests {
    // MARK: - Tour helpers

    /// Taps a response button, which stacks an emoji above its word.
    func tapResponse(_ name: String) -> Bool {
        let button = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", name)
        ).firstMatch
        guard button.waitForExistence(timeout: 6), bringIntoView(button) else { return false }
        button.tap()
        return true
    }

    /// The celebration overlay covers the screen until dismissed.
    func dismissCelebration() {
        let awesome = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Awesome' OR label CONTAINS[c] 'Nice'")
        ).firstMatch
        if awesome.waitForExistence(timeout: 3), awesome.isHittable {
            awesome.tap()
            settle(0.8)
        }
    }

    /// Closes whichever sheet happens to be up.
    func dismissAnySheet() {
        for _ in 0..<3 {
            let cancel = app.buttons.containing(
                NSPredicate(format: "label BEGINSWITH[c] 'Cancel'")
            ).firstMatch
            if cancel.exists && cancel.isHittable {
                cancel.tap()
            } else {
                app.swipeDown()
            }
            settle(0.7)
            if app.tabBars.buttons["Requests"].isHittable { return }
        }
    }

    /// Saying when you are not free, and seeing who else isn't.
    ///
    /// The panel reports the *selected* day and the calendar opens on today, so the seeded busy
    /// day has to be tapped or the frame shows an empty panel and proves nothing.
    func tourAvailability() {
        tab("Calendar").tap()
        settle(1.0)

        let calendar = Calendar.current
        if let busyDay = calendar.date(byAdding: .day, value: 2, to: Date()) {
            let cell = app.staticTexts[String(calendar.component(.day, from: busyDay))]
            if cell.waitForExistence(timeout: 6), cell.isHittable {
                cell.tap()
                settle(0.8)
            }
        }

        _ = bringIntoView(app.buttons["toggleUnavailable"])
        shoot("availability-who-is-not-free")

        let toggle = app.buttons["toggleUnavailable"]
        if toggle.exists && toggle.isHittable {
            toggle.tap()
            settle(1.4)
            shoot("availability-blocked-out")
        }
    }

    /// How often this group's plans actually happen — the number the app exists to change.
    func tourFollowThrough() {
        tab("Activities").tap()
        settle(1.0)
        _ = bringIntoView(text("this will show how many"))
        shoot("follow-through")
    }

    /// Five kinds of alert, each with its own switch.
    ///
    /// Filmable only because of `-MGShowNotificationSettings`: iOS hides these until push
    /// permission is granted and a simulator never grants it.
    func tourNotificationSettings() {
        tab("Profile").tap()
        settle(1.0)
        let toggle = app.switches.containing(
            NSPredicate(format: "label CONTAINS[c] 'New requests'")
        ).firstMatch
        _ = bringIntoView(toggle)
        shoot("notification-settings")
        if toggle.exists && toggle.isHittable {
            toggle.tap()
            settle(1.0)
            shoot("notification-switched-off")
        }
    }

    /// A code that admits somebody to one plan and nothing else.
    func tourPlanInvite() {
        tab("Requests").tap()
        settle(0.8)
        guard open("Date night this Friday?") else { return }
        let create = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Create a code for this plan'")
        ).firstMatch
        guard bringIntoView(create) else { return }
        shoot("plan-invite-offered")
        create.tap()
        settle(1.6)
        _ = bringIntoView(app.buttons["Cancel this plan code"])
        shoot("plan-invite-code")
        back()
    }

    /// Saved plans are findable again, which is the whole point of saving one.
    func tourFeedFilter() {
        tab("Requests").tap()
        settle(0.8)
        let filter = app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH[c] 'Filter requests'")
        ).firstMatch
        guard filter.waitForExistence(timeout: 6) else { return }
        filter.tap()
        settle(1.0)
        shoot("feed-filter")
        if app.buttons["All"].exists { app.buttons["All"].tap() }
        settle(0.6)
    }

    /// The operator panel — every section, including the two built this week.
    ///
    /// Reachable only with `-MGAdmin`. The tab is a convenience gate; `firestore.rules` refuses
    /// the underlying reads to anyone without a server-issued claim regardless.
    func tourAdminPanel() {
        guard app.tabBars.buttons["Admin"].waitForExistence(timeout: 8) else { return }
        app.tabBars.buttons["Admin"].tap()
        settle(1.2)
        shoot("admin-overview")

        for section in ["Users", "Requests", "Reports", "Outcomes"] {
            let button = app.segmentedControls.buttons[section].exists
                ? app.segmentedControls.buttons[section]
                : app.buttons[section]
            for _ in 0..<4 where !button.exists || !button.isHittable {
                app.swipeLeft()
                settle(0.4)
            }
            guard button.exists, button.isHittable else { continue }
            button.tap()
            settle(1.2)
            shoot("admin-\(section.lowercased())")

            // The two worth showing in motion rather than as a list.
            if section == "Reports", app.buttons["Actioned"].exists {
                app.buttons["Actioned"].tap()
                settle(1.4)
                shoot("admin-report-closed")
            }
            if section == "Outcomes" {
                // Scroll to the caveat, not to the breakdown: the breakdown is already on screen,
                // so that frame came out byte-identical to the one above it.
                _ = bringIntoView(text("Collection began"))
                shoot("admin-outcomes-caveat")
            }
        }
    }

    func tourTheFourTabs() {
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

    // MARK: - The week's work, which no recording had ever shown

    /// A trip, end to end: a range on the feed, how many nights, whose clock it is on, and the
    /// itinerary day by day.
    ///
    /// None of this appeared in any recording until now. The features shipped with unit tests,
    /// rules tests and their own UI tests — but the tour is what somebody *watches*, and a
    /// four-night holiday looked exactly like a Tuesday dinner in every frame ever filmed.
    func tourTrip() {
        tab("Requests").tap()
        settle(0.8)
        let trip = app.staticTexts["Barcelona in May?"]
        guard trip.waitForExistence(timeout: 12), bringIntoView(trip) else { return }
        // The card, where the range has to read as a range rather than a single date.
        shoot("trip-range-on-the-feed")

        trip.tap()
        settle(1.0)
        shoot("trip-detail-nights-and-clock")

        // The itinerary is below the fold on most devices.
        // One frame, not two. The detail shot above already carries the top of the itinerary, and
        // scrolling once reaches the bottom of it — all five days, the empty ones, and the
        // undated item — so a second shot photographed an identical screen twice. Both attempts
        // were reported by the contact-sheet check as "a modal probably stayed open"; neither
        // time was that true. The itinerary simply fits.
        app.swipeUp()
        settle(0.6)
        shoot("trip-itinerary-by-day")

        // Adding something, since the itinerary is the one new feature with a write path.
        let add = app.buttons["Add something to the itinerary"]
        if add.exists && add.isHittable {
            add.tap()
            settle(1.0)
            shoot("trip-itinerary-add-sheet")
            let field = app.textFields["itineraryTitle"]
            if field.waitForExistence(timeout: 6) {
                field.tap()
                field.typeText("Tapas near the beach")
                settle(0.5)
                shoot("trip-itinerary-add-typed")
            }
            let cancel = app.buttons["Cancel"]
            if cancel.exists { cancel.tap() }
            settle(0.8)
        }
        back()
    }

    /// The compose sheet's "Over several days", which is the only way a trip gets made.
    func tourComposeATrip() {
        tab("Requests").tap()
        settle(0.6)
        app.buttons["Create new request or spontaneous invite"].tap()
        settle(0.8)
        let newRequest = app.buttons["New Request"]
        if newRequest.waitForExistence(timeout: 5) { newRequest.tap() }
        guard app.navigationBars["New Request"].waitForExistence(timeout: 12) else {
            dismissAnySheet()
            return
        }

        let suggestTime = app.switches["Suggest a time"]
        for _ in 0..<8 where !suggestTime.exists { app.swipeUp(); settle(0.3) }
        if suggestTime.exists {
            // A Toggle in a Form is one element spanning the row, so a plain tap lands on the
            // label and changes nothing. The trailing edge is where the switch actually is.
            suggestTime.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            settle(0.8)
        }
        let overDays = app.switches["Over several days"]
        for _ in 0..<8 where !overDays.exists { app.swipeUp(); settle(0.3) }
        shoot("compose-over-several-days")
        if overDays.exists {
            overDays.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            settle(0.8)
            shoot("compose-trip-end-date")
        }
        dismissAnySheet()
    }

    /// The group energy card — how alive a group is, and what to do about it.
    func tourGroupEnergy() {
        tab("Activities").tap()
        settle(1.0)
        // By the sentence the card carries, not the word "energy" — which appears nowhere in it.
        // `GroupEnergyCard` renders a group name, a level and `energy.reason`; the first version
        // of this searched for "energy" and photographed nothing at all.
        let sentence = app.staticTexts.containing(
            NSPredicate(
                format: "label CONTAINS[c] 'Last got together'"
                    + " OR label CONTAINS[c] 'Nothing to go on yet'"
                    + " OR label CONTAINS[c] 'coming up'"
            )
        ).firstMatch
        guard sentence.waitForExistence(timeout: 10), bringIntoView(sentence) else { return }
        shoot("activities-group-energy")
    }

    /// Joining by a code, which the tour only ever showed the *issuing* half of.
    func tourJoinByCode() {
        tab("Profile").tap()
        settle(1.0)
        // By label. "Enter invite code" is the *placeholder*; the accessibility label is
        // "Invite code". The placeholder query matched well enough to exist and be photographed,
        // and then `typeText` threw "Neither element nor any descendant has keyboard focus" —
        // which ended the whole tour despite `continueAfterFailure`, taking the report and admin
        // sections with it.
        let field = app.textFields["Invite code"]
        guard field.waitForExistence(timeout: 8), bringIntoView(field) else { return }
        shoot("join-have-a-code")
        field.tap()
        // Only type once the keyboard is actually up. A tap that does not take focus is the
        // ordinary case on a scrolled form, and typing into it is an exception, not a failure
        // worth losing the rest of the recording over.
        if app.keyboards.element.waitForExistence(timeout: 5) {
            field.typeText("MG7QP2")
            settle(0.6)
            shoot("join-code-entered")
        }
        // Deliberately not submitted: joining a group you are already in fails, and the tour
        // should show the affordance rather than an error alert nobody asked for.
        dismissAnySheet()
    }

    /// Reporting, which App Review guideline 1.2 requires and no recording had shown.
    func tourReportSomeone() {
        guard open("Sunday roast?") else { return }
        let more = app.buttons["More actions"]
        guard more.waitForExistence(timeout: 6) else { back(); return }
        more.tap()
        settle(0.8)
        shoot("report-menu")
        let report = app.buttons["Report this"]
        if report.waitForExistence(timeout: 4) {
            report.tap()
            settle(1.0)
            shoot("report-sheet")
        }
        dismissAnySheet()
        back()
    }

    /// A spontaneous invite, all the way through to it appearing in the feed.
    ///
    /// The first version stopped at the sheet, so the video showed the screen and never which
    /// idea was chosen, how long it lasted, or that anything was sent.
    func tourSpontaneous() {
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
