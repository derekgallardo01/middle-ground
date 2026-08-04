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

    /// Accepting a request, and the celebration that follows.
}
