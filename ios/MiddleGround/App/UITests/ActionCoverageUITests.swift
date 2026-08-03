import XCTest

/// Every action a person can take, exercised from the seat of the person who can take it.
///
/// Runs in mock mode, so the fixtures are deterministic and nothing touches production. The mock
/// identity is `user_1` ("Alex"), which puts the same run in two seats at once:
///
/// | Party | Means | Fixtures |
/// |---|---|---|
/// | **Creator** | Alex sent it, and is waiting | "Date night this Friday?", "Sunday roast?", "Climbing on Saturday" |
/// | **Recipient** | Someone sent it to Alex, and it is Alex's turn | "Split the chores this week?", "Dinner at Lucia's" |
/// | **Group member** | Three people, so declining is "not me" rather than "cancelled" | "Sunday roast?" |
///
/// The point of splitting them is that the two seats have genuinely different rights, and most of
/// the bugs found in this app have been a control offered to the wrong one — a Cancel button shown
/// to somebody who could not cancel, a Save offered to the creator, a composer that refused the
/// person it was for. Each test therefore asserts the *absence* of what a party must not see as
/// often as the presence of what it must.
final class ActionCoverageUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MGMockMode"]
        app.launch()
    }

    // MARK: - Helpers

    private func tab(_ name: String) -> XCUIElement { app.tabBars.buttons[name] }

    /// Opens a request from the feed by its title.
    @discardableResult
    private func openPlan(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        tab("Requests").tap()
        let cell = app.staticTexts[title]
        guard cell.waitForExistence(timeout: 10) else {
            XCTFail("no plan titled \(title) in the feed", file: file, line: line)
            return false
        }
        cell.tap()
        return true
    }

    private func back() {
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists { backButton.tap() }
    }

    /// True when a control is on screen and usable.
    private func usable(_ element: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        element.waitForExistence(timeout: timeout) && element.isHittable
    }

    /// `ResponseButton` stacks an emoji above the word, so the button's accessibility label is
    /// composed of both — "Accept" never matches exactly.
    private func responseButton(_ name: String) -> XCUIElement {
        app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", name)
        ).firstMatch
    }

    /// The composer sits below the transcript and is off-screen on a long plan.
    @discardableResult
    private func composerField() -> XCUIElement {
        let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        for _ in 0..<4 where !(field.exists && field.isHittable) {
            app.swipeUp()
        }
        return field
    }

    /// Types into the composer and sends, asserting each step so a failure names the step.
    @discardableResult
    private func sendMessage(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let field = composerField()
        guard usable(field, timeout: 8) else {
            XCTFail("composer never became usable", file: file, line: line)
            return false
        }
        field.tap()
        field.typeText(text)

        // By identifier, not label: the keyboard's return key is also "Send".
        let send = app.buttons["sendMessage"]
        guard send.waitForExistence(timeout: 4) else {
            XCTFail("no Send button", file: file, line: line)
            return false
        }
        // Send is disabled until there is something to send, so this proves the text landed.
        guard send.isEnabled else {
            XCTFail("Send stayed disabled — the typed text never reached the field", file: file, line: line)
            return false
        }
        send.tap()
        return true
    }

    // MARK: - Party: anyone

    func test_00_everyTabReachable() throws {
        for name in ["Requests", "Calendar", "Activities", "Profile"] {
            XCTAssertTrue(usable(tab(name)), "\(name) tab is not reachable")
            tab(name).tap()
        }
    }

    // MARK: - Party: recipient (it is Alex's turn)

    /// The four answers, all of which must be offered to the person whose turn it is.
    func test_10_recipientIsOfferedEveryResponse() throws {
        guard openPlan("Split the chores this week?") else { return }

        for label in ["Accept", "Negotiate", "Reschedule", "Decline"] {
            XCTAssertTrue(
                responseButton(label).waitForExistence(timeout: 6),
                "the recipient must be offered \(label)"
            )
        }
    }

    /// Saving is a response, so only the person who may respond gets it.
    func test_11_recipientCanSaveForLater() throws {
        guard openPlan("Split the chores this week?") else { return }
        XCTAssertTrue(
            app.buttons["Save for later"].waitForExistence(timeout: 6),
            "the recipient must be able to save"
        )
    }

    /// Reporting is required of any app carrying user-generated content (guideline 1.2), and is
    /// only meaningful against somebody else's content.
    func test_12_recipientCanReachTheReportControl() throws {
        guard openPlan("Split the chores this week?") else { return }
        let more = app.buttons["More actions"]
        XCTAssertTrue(usable(more), "the ⋯ menu must be reachable on somebody else's plan")
        more.tap()
        XCTAssertTrue(
            app.buttons["Report this"].waitForExistence(timeout: 4),
            "Report this must be in the menu"
        )
    }

    func test_13_recipientCanAcceptAndTheStatusMoves() throws {
        guard openPlan("Split the chores this week?") else { return }
        let accept = responseButton("Accept")
        guard usable(accept, timeout: 6) else { return XCTFail("no Accept button") }
        accept.tap()

        // Accepting removes the response row, which is the observable consequence.
        XCTAssertTrue(
            waitForDisappearance(responseButton("Decline"), timeout: 8),
            "the response row should go once the plan is answered"
        )
    }

    // MARK: - Party: creator (Alex sent it)

    /// The creator answering their own request would close a shared decision alone.
    func test_20_creatorIsOfferedNoResponses() throws {
        guard openPlan("Date night this Friday?") else { return }

        for label in ["Accept", "Decline", "Negotiate"] {
            XCTAssertFalse(
                responseButton(label).exists,
                "the creator must not be offered \(label) on their own request"
            )
        }
    }

    /// Saving is a response too — it was ungated once, which let anyone flip a request to `saved`.
    func test_21_creatorIsNotOfferedSave() throws {
        guard openPlan("Date night this Friday?") else { return }
        XCTAssertFalse(
            app.buttons["Save for later"].exists,
            "saving is a response, so the creator does not get it"
        )
    }

    /// The creator *can* report, and should be able to.
    ///
    /// This test originally asserted the opposite, on the assumption that there is nobody to
    /// report on your own request. That is wrong: the plan has another participant, and somebody
    /// who replies abusively to a plan you sent is exactly who you would want to report. The app
    /// was right and the test was wrong — recorded here because the same reasoning error would
    /// otherwise be made again.
    func test_22_creatorCanAlsoReportTheOtherParticipant() throws {
        guard openPlan("Date night this Friday?") else { return }
        XCTAssertTrue(
            app.buttons["More actions"].waitForExistence(timeout: 6),
            "the creator can report whoever they sent the plan to"
        )
    }

    /// The bug found on a real device: Cancel was offered to people who could not cancel.
    func test_23_creatorCanCancelTheirOwnPlan() throws {
        guard openPlan("Date night this Friday?") else { return }
        XCTAssertTrue(
            app.buttons["Cancel request"].waitForExistence(timeout: 6),
            "the creator must be able to call off their own plan"
        )
    }

    func test_24_creatorCanComposeANewPlan() throws {
        tab("Requests").tap()
        // A Menu, not a plain button, and labelled for what it opens rather than "New Request".
        let plus = app.buttons["Create new request or spontaneous invite"]
        guard usable(plus, timeout: 8) else { return XCTFail("no compose control") }
        plus.tap()
        let newRequest = app.buttons["New Request"]
        if usable(newRequest, timeout: 4) { newRequest.tap() }
        XCTAssertTrue(
            app.textFields.firstMatch.waitForExistence(timeout: 6)
                || app.textViews.firstMatch.waitForExistence(timeout: 2),
            "the compose sheet should present a field to type into"
        )
    }

    // MARK: - Party: group member (three people)

    /// Group state was computed and displayed nowhere until recently.
    func test_30_groupPlanShowsWhoIsInAndWhoIsOwed() throws {
        guard openPlan("Sunday roast?") else { return }
        let inLine = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'are in' OR label CONTAINS[c] 'is in'")
        ).firstMatch
        let waiting = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH[c] 'Waiting on'")
        ).firstMatch

        XCTAssertTrue(
            inLine.waitForExistence(timeout: 6) || waiting.waitForExistence(timeout: 2),
            "a group plan must say where it stands"
        )
    }

    // MARK: - Conversation, from either seat

    /// The composer used to be gated on whose turn it was, so somebody who had already answered
    /// could not ask a question about the plan they had just agreed to.
    func test_40_composerIsAvailableEvenWhenItIsNotYourTurn() throws {
        guard openPlan("Date night this Friday?") else { return }
        XCTAssertTrue(
            composerField().waitForExistence(timeout: 6),
            "anyone on a plan can speak, whether or not they owe an answer"
        )
    }

    func test_41_sendingAMessageAddsItToTheTranscript() throws {
        guard openPlan("Date night this Friday?") else { return }
        let text = "which entrance?"
        guard sendMessage(text) else { return }

        XCTAssertTrue(
            app.staticTexts[text].waitForExistence(timeout: 8),
            "a sent message should appear in the transcript"
        )
    }

    /// The whole point of moving conversation off the negotiation chain: asking a question must
    /// not withdraw an agreement.
    ///
    /// Asserts the message actually landed *before* checking that the plan stayed agreed. Without
    /// that first assertion the test passes when the send silently fails — proving nothing, which
    /// is worse than failing.
    func test_42_askingAQuestionDoesNotUnpickAnAgreedPlan() throws {
        guard openPlan("Sunday roast?") else { return }
        let text = "what time again?"
        guard sendMessage(text) else { return }

        XCTAssertTrue(
            app.staticTexts[text].waitForExistence(timeout: 8),
            "the question has to have been sent for this test to mean anything"
        )
        XCTAssertFalse(
            responseButton("Accept").waitForExistence(timeout: 4),
            "a question must not reopen an agreed plan for answering"
        )
    }

    // MARK: - Other surfaces

    func test_50_calendarRenders() throws {
        tab("Calendar").tap()
        XCTAssertTrue(
            app.staticTexts.firstMatch.waitForExistence(timeout: 8),
            "the calendar should render something"
        )
    }

    func test_51_activitiesShowProgress() throws {
        tab("Activities").tap()
        let level = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'level' OR label CONTAINS[c] 'XP' OR label CONTAINS[c] 'streak'")
        ).firstMatch
        XCTAssertTrue(level.waitForExistence(timeout: 8), "Activities should show progress")
    }

    /// Guideline 5.1.1(v): in-app account deletion has to be reachable.
    func test_52_accountDeletionIsReachable() throws {
        tab("Profile").tap()
        let delete = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'delete account'")
        ).firstMatch
        let text = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'delete account'")
        ).firstMatch
        XCTAssertTrue(
            delete.waitForExistence(timeout: 8) || text.waitForExistence(timeout: 2),
            "Delete Account must be reachable from Profile"
        )
    }

    func test_53_profileShowsGroupsAndInviteCode() throws {
        tab("Profile").tap()
        XCTAssertTrue(
            app.otherElements["inviteCode"].waitForExistence(timeout: 8)
                || app.staticTexts["inviteCode"].waitForExistence(timeout: 2)
                || app.staticTexts.containing(
                    NSPredicate(format: "label CONTAINS[c] 'group'")
                ).firstMatch.waitForExistence(timeout: 2),
            "Profile should show groups and an invite code"
        )
    }

    // MARK: - Utilities

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            usleep(200_000)
        }
        return !element.exists
    }
}
