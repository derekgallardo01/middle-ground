import XCTest

/// The actions that were only ever checked for *presence*, driven for real.
///
/// The existing suites answer "is the control there" and "is the right person offered it". This
/// one answers "does pressing it do the thing" — confirming a plan happened, putting points on
/// one, sharing a location, calling something off with a reason, opening a plan up to an
/// outsider, and changing what you are notified about.
///
/// Every test leaves a frame behind, so the verification log can point at what was on screen.
final class E2EActionsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var extraArguments: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() {
        app = XCUIApplication()
        app.launchArguments = ["-MGMockMode"] + extraArguments
        app.launch()
    }

    // MARK: - Helpers

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func tab(_ name: String) -> XCUIElement { app.tabBars.buttons[name] }

    @discardableResult
    private func openPlan(_ title: String) -> Bool {
        tab("Requests").tap()
        let cell = app.staticTexts[title]
        guard cell.waitForExistence(timeout: 15) else {
            XCTFail("no plan titled \(title)")
            return false
        }
        cell.tap()
        return true
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }

    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    private func button(containing fragment: String) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    // MARK: - Did it happen

    /// The single answer everything about reliability is built on, and it was never driven.
    func test_action_01_confirmingAPlanHappened() throws {
        launch()
        guard openPlan("Coffee on Monday") else { return }

        let yes = button(containing: "Yes, it did")
        guard scrollTo(yes) else { return XCTFail("no way to confirm the plan happened") }
        shoot("action-01-asked-if-it-happened")

        yes.tap()

        // The question retires once answered — either into a settled summary or a celebration.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && yes.exists { usleep(200_000) }
        XCTAssertFalse(yes.exists, "answering should settle the question")
        shoot("action-01-confirmed")
    }

    func test_action_02_sayingAPlanDidNotHappen() throws {
        launch()
        guard openPlan("Coffee on Monday") else { return }

        let no = button(containing: "It didn't")
        guard scrollTo(no) else { return XCTFail("no way to say it did not happen") }
        no.tap()

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && no.exists { usleep(200_000) }
        XCTAssertFalse(no.exists, "answering should settle the question")
        shoot("action-02-did-not-happen")
    }

    // MARK: - Points on a plan

    /// Staking was only ever checked as a row that renders.
    func test_action_03_puttingPointsOnAPlan() throws {
        launch()
        guard openPlan("Date night this Friday?") else { return }

        let stake = button(containing: "25")
        guard scrollTo(stake) else { return XCTFail("no stake amounts offered") }
        shoot("action-03-stake-offered")

        stake.tap()

        XCTAssertTrue(
            scrollTo(text(containing: "25 points")),
            "staking should say what is riding on the plan"
        )
        shoot("action-03-stake-placed")
    }

    // MARK: - Calling a plan off

    /// Cancelling asks why, and the reason is the point — a plan that vanishes tells nobody
    /// anything.
    func test_action_04_cancellingAsksWhyAndTakesAnAnswer() throws {
        launch()
        guard openPlan("Date night this Friday?") else { return }

        let cancel = button(containing: "Cancel request")
        guard scrollTo(cancel) else { return XCTFail("the creator should be able to call it off") }
        cancel.tap()

        XCTAssertTrue(
            text(containing: "Why are you cancelling").waitForExistence(timeout: 8),
            "cancelling should ask for a reason"
        )
        shoot("action-04-cancel-asks-why")

        let reason = button(containing: "Something came up")
        guard reason.waitForExistence(timeout: 6) else { return XCTFail("no reasons offered") }
        reason.tap()

        XCTAssertTrue(
            text(containing: "Cancelled").waitForExistence(timeout: 10),
            "the plan should end up cancelled, with the reason on the record"
        )
        shoot("action-04-cancelled")
    }

    // MARK: - Inviting somebody to one plan only

    /// A code that admits somebody to this plan and nothing else — deliberately not discovery.
    func test_action_05_creatingAndRevokingAPlanInvite() throws {
        launch()
        guard openPlan("Date night this Friday?") else { return }

        let create = button(containing: "Create a code for this plan")
        guard scrollTo(create) else { return XCTFail("no plan-invite control") }
        create.tap()

        let revoke = app.buttons["Cancel this plan code"]
        XCTAssertTrue(revoke.waitForExistence(timeout: 10), "a created code should be revocable")
        shoot("action-05-plan-invite-created")

        revoke.tap()
        XCTAssertTrue(
            create.waitForExistence(timeout: 10),
            "revoking should offer to create one again"
        )
        shoot("action-05-plan-invite-revoked")
    }

    // MARK: - Notifications

    /// Five kinds of alert, each with its own switch, and nothing on behind your back. The
    /// switches are hidden until iOS grants permission, which a simulator never does.
    func test_action_06_notificationSwitchesCanBeChanged() throws {
        extraArguments = ["-MGShowNotificationSettings"]
        launch()
        tab("Profile").tap()

        // A per-kind switch, not the master one. "Push Notifications" asks iOS for permission,
        // which a simulator under test never grants — so it correctly stays off, and asserting
        // that it flips would be asserting the app ignores the OS.
        let toggle = app.switches.containing(
            NSPredicate(format: "label CONTAINS[c] 'New requests'")
        ).firstMatch
        guard scrollTo(toggle, swipes: 10) else { return XCTFail("no per-kind notification switches") }
        shoot("action-06-notification-settings")

        let before = toggle.value as? String
        toggle.tap()
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline && (toggle.value as? String) == before { usleep(200_000) }
        XCTAssertNotEqual(toggle.value as? String, before, "a switch should actually switch")
        shoot("action-06-notification-changed")
    }

    // MARK: - Reporting the right person

    /// In a group of three the subject is a question, and guessing it was the bug.
    func test_action_07_reportingInAGroupAsksWho() throws {
        launch()
        guard openPlan("Sunday roast?") else { return }

        let more = app.buttons["More actions"]
        guard more.waitForExistence(timeout: 10) else { return XCTFail("no overflow menu") }
        more.tap()

        let report = button(containing: "Report this")
        guard report.waitForExistence(timeout: 6) else { return XCTFail("no report action") }
        report.tap()

        XCTAssertTrue(
            text(containing: "Who is this about").waitForExistence(timeout: 8),
            "a group plan must ask who is being reported rather than picking somebody"
        )
        shoot("action-07-report-asks-who")
    }

    // MARK: - Contrast on filled surfaces

    /// Photographs the three places where text sits on an indigo fill.
    ///
    /// A UI test cannot assert a colour, so this exists to produce the frames — the check is a
    /// person looking at them. Worth having because the failure is invisible to every other kind
    /// of test: the text is present, hittable and correctly labelled, and simply cannot be read.
    func test_action_09_textOnIndigoFills() throws {
        launch()

        // 1. The chosen category, which is the one chip that must read as chosen.
        tab("Requests").tap()
        let fab = app.buttons["Create new request or spontaneous invite"]
        guard fab.waitForExistence(timeout: 12) else { return XCTFail("no compose button") }
        fab.tap()
        if app.buttons["New Request"].waitForExistence(timeout: 6) {
            app.buttons["New Request"].tap()
        }
        let couple = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Couple' OR label CONTAINS[c] 'Relationship'")
        ).firstMatch
        if couple.waitForExistence(timeout: 8), couple.isHittable { couple.tap() }
        shoot("contrast-01-selected-category")

        // 2. Your own messages, which sit on an indigo bubble.
        let cancel = app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH[c] 'Cancel'")
        ).firstMatch
        if cancel.exists && cancel.isHittable { cancel.tap() }
        guard openPlan("Sunday roast?") else { return }
        _ = scrollTo(text(containing: "I'm in"), swipes: 8)
        shoot("contrast-02-your-own-message")
    }

    // MARK: - Home

    /// Saved plans are findable again, which is the whole point of saving one.
    func test_action_08_theFeedCanBeFiltered() throws {
        launch()
        tab("Requests").tap()

        let filter = app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH[c] 'Filter requests'")
        ).firstMatch
        guard filter.waitForExistence(timeout: 15) else { return XCTFail("no filter control") }
        filter.tap()

        XCTAssertTrue(
            app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Saved'")).firstMatch
                .waitForExistence(timeout: 6),
            "the feed should offer a saved filter"
        )
        shoot("action-08-feed-filters")
    }
}
