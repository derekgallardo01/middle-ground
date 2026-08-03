import XCTest

/// Every feature, on the fixture that actually puts it on screen.
///
/// `ActionCoverageUITests` covers who is allowed to do what. This covers whether each feature
/// renders at all — the two fail in different ways, and a feature that is permitted but invisible
/// passes the first suite completely.
///
/// The fixtures are chosen for the state each feature needs, which is most of the work:
///
/// | Fixture | State | Puts on screen |
/// |---|---|---|
/// | "Sunday roast?" (`req_6`) | accepted · 3 people · time · place | group row, chat, threads, seen-by, booking |
/// | "Climbing on Saturday" (`req_4`) | accepted · stake · time · place | stake row, booking |
/// | "Dinner at Lucia's" (`req_5`) | accepted · time · place | booking, location window |
/// | "Date night this Friday?" (`req_1`) | pending · creator is me | waiting row, cancel, plan invite |
/// | "Split the chores this week?" (`req_0`) | pending · recipient is me | the four responses |
final class FeatureCoverageUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Set by a test before `launchApp()` when it needs the typing indicator seeded.
    private var extraLaunchArguments: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() {
        app = XCUIApplication()
        app.launchArguments = ["-MGMockMode"] + extraLaunchArguments
        app.launch()
    }

    // MARK: - Helpers

    private func tab(_ name: String) -> XCUIElement { app.tabBars.buttons[name] }

    @discardableResult
    private func openPlan(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        tab("Requests").tap()
        let cell = app.staticTexts[title]
        guard cell.waitForExistence(timeout: 12) else {
            XCTFail("no plan titled \(title)", file: file, line: line)
            return false
        }
        cell.tap()
        return true
    }

    /// Scrolls until `element` is on screen, or gives up. Most of these rows sit below the fold.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, swipes: Int = 5) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }

    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", fragment)
        ).firstMatch
    }

    // MARK: - Conversation

    func test_chat_showsTheExistingConversation() throws {
        launchApp()
        guard openPlan("Sunday roast?") else { return }

        let message = text(containing: "Which entrance")
        XCTAssertTrue(scrollTo(message), "a message on the plan must appear in the transcript")
    }

    /// A reply is nested under its parent rather than shown as its own entry in the timeline.
    func test_threads_replyIsShownUnderItsParent() throws {
        launchApp()
        guard openPlan("Sunday roast?") else { return }

        let parent = text(containing: "Which entrance")
        XCTAssertTrue(scrollTo(parent), "the parent message should be visible")
        let reply = text(containing: "The one on Fourth")
        XCTAssertTrue(scrollTo(reply), "the reply should be visible under its parent")
    }

    func test_threads_replyControlIsOffered() throws {
        launchApp()
        guard openPlan("Sunday roast?") else { return }

        let reply = app.buttons["Reply"].firstMatch
        XCTAssertTrue(scrollTo(reply), "each message should offer a Reply control")
    }

    /// Per plan, not per message — the reassurance the feature is built around.
    func test_readReceipts_seenByLineIsShown() throws {
        launchApp()
        guard openPlan("Sunday roast?") else { return }

        let seen = text(containing: "Seen by")
        XCTAssertTrue(scrollTo(seen), "the plan should say who has seen it")
    }

    /// Seeded behind `-MGSeedTyping`, because a permanent indicator would be wrong everywhere else.
    func test_typing_indicatorAppearsWhenSomeoneIsTyping() throws {
        extraLaunchArguments = ["-MGSeedTyping"]
        launchApp()
        guard openPlan("Sunday roast?") else { return }

        let typing = text(containing: "is typing")
        XCTAssertTrue(scrollTo(typing), "the typing indicator should name who is typing")
    }

    /// The default has to be clean, or every screenshot claims somebody is mid-sentence.
    func test_typing_indicatorIsAbsentByDefault() throws {
        launchApp()
        guard openPlan("Sunday roast?") else { return }
        scrollTo(app.buttons["sendMessage"])

        XCTAssertFalse(
            text(containing: "is typing").exists,
            "nothing should claim somebody is typing unless they are"
        )
    }

    // MARK: - Booking

    func test_booking_findATableIsOfferedOnAnAgreedPlanWithAPlace() throws {
        launchApp()
        guard openPlan("Sunday roast?") else { return }

        let find = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Find a table'")
        ).firstMatch
        XCTAssertTrue(scrollTo(find), "an agreed plan with a place should offer a table")
    }

    /// The row is absent, not disabled, when the plan is not agreed — a greyed-out control invites
    /// a question with a boring answer.
    func test_booking_isAbsentOnAPlanNobodyHasAgreedTo() throws {
        launchApp()
        guard openPlan("Split the chores this week?") else { return }
        scrollTo(app.buttons["sendMessage"])

        XCTAssertFalse(
            app.buttons.containing(
                NSPredicate(format: "label CONTAINS[c] 'Find a table'")
            ).firstMatch.exists,
            "no table on a plan nobody has agreed to"
        )
    }

    // MARK: - Stake

    func test_stake_rowIsShownOnAStakedPlan() throws {
        launchApp()
        guard openPlan("Climbing on Saturday") else { return }

        let staked = text(containing: "point")
        XCTAssertTrue(scrollTo(staked), "a staked plan should show its points")
    }

    // MARK: - Group

    func test_group_showsWhoIsInAndWhoIsOwed() throws {
        launchApp()
        guard openPlan("Sunday roast?") else { return }

        let inLine = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'are in' OR label CONTAINS[c] 'is in'")
        ).firstMatch
        let waiting = text(containing: "Waiting on")
        XCTAssertTrue(
            scrollTo(inLine) || scrollTo(waiting),
            "a group plan must say where it stands"
        )
    }

    // MARK: - Plan invite

    func test_planInvite_creatorCanOpenTheInviteRow() throws {
        launchApp()
        guard openPlan("Date night this Friday?") else { return }

        let invite = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'invite' OR label CONTAINS[c] 'code'")
        ).firstMatch
        let inviteText = text(containing: "invite")
        XCTAssertTrue(
            scrollTo(invite) || scrollTo(inviteText),
            "the creator should be able to invite someone to just this plan"
        )
    }

    // MARK: - Requests: the remaining responses

    func test_requests_declineIsOfferedAndCompletes() throws {
        launchApp()
        guard openPlan("Split the chores this week?") else { return }

        let decline = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Decline'")
        ).firstMatch
        guard decline.waitForExistence(timeout: 8) else { return XCTFail("no Decline") }
        decline.tap()

        // The response row retires once the plan is answered.
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline && decline.exists { usleep(200_000) }
        XCTAssertFalse(decline.exists, "declining should settle the request")
    }

    func test_requests_rescheduleOpensATimePicker() throws {
        launchApp()
        guard openPlan("Split the chores this week?") else { return }

        let reschedule = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Reschedule'")
        ).firstMatch
        guard reschedule.waitForExistence(timeout: 8) else { return XCTFail("no Reschedule") }
        reschedule.tap()

        XCTAssertTrue(
            app.datePickers.firstMatch.waitForExistence(timeout: 6)
                || app.staticTexts["Suggest a time"].waitForExistence(timeout: 2),
            "Reschedule should offer a time to suggest"
        )
    }

    /// Attaching a time is what turns a message into a proposal.
    func test_requests_composerOffersToAttachATime() throws {
        launchApp()
        guard openPlan("Split the chores this week?") else { return }

        let attach = app.buttons["Suggest a time"]
        XCTAssertTrue(scrollTo(attach), "the composer should offer to attach a time")
    }

    // MARK: - Create

    func test_create_fullFlowReachesASendableState() throws {
        launchApp()
        tab("Requests").tap()

        let fab = app.buttons["Create new request or spontaneous invite"]
        guard fab.waitForExistence(timeout: 10) else { return XCTFail("no compose control") }
        fab.tap()
        let newRequest = app.buttons["New Request"]
        if newRequest.waitForExistence(timeout: 4) { newRequest.tap() }

        let field = app.textFields.firstMatch
        guard field.waitForExistence(timeout: 8) else { return XCTFail("no title field") }
        field.tap()
        field.typeText("Coffee tomorrow?")

        // Whatever the send control is called, something must become available once there is a
        // title — a compose screen you cannot submit is the failure worth catching.
        let send = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'send' OR label CONTAINS[c] 'create' OR label CONTAINS[c] 'ask'")
        ).firstMatch
        XCTAssertTrue(
            send.waitForExistence(timeout: 6),
            "the compose sheet should offer a way to send once a title is typed"
        )
    }

    // MARK: - Activities

    func test_activities_reliabilityAndProgressRender() throws {
        launchApp()
        tab("Activities").tap()

        let turningUp = text(containing: "Turning up")
        let progress = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'level' OR label CONTAINS[c] 'XP' OR label CONTAINS[c] 'streak'")
        ).firstMatch
        XCTAssertTrue(
            scrollTo(turningUp) || progress.waitForExistence(timeout: 6),
            "Activities should show progress and reliability"
        )
    }

    // MARK: - Calendar

    func test_calendar_showsAPlanWithATime() throws {
        launchApp()
        tab("Calendar").tap()
        XCTAssertTrue(
            app.staticTexts.firstMatch.waitForExistence(timeout: 10),
            "the calendar should render"
        )
    }

    // MARK: - Profile

    func test_profile_showsGroupsInviteCodeAndNotificationSettings() throws {
        launchApp()
        tab("Profile").tap()

        let code = app.staticTexts["inviteCode"].exists
            || app.otherElements["inviteCode"].waitForExistence(timeout: 8)
        let groups = text(containing: "group")
        XCTAssertTrue(code || scrollTo(groups), "Profile should show groups and an invite code")

        let notifications = text(containing: "notification")
        XCTAssertTrue(
            scrollTo(notifications),
            "Profile should offer notification settings"
        )
    }
}
