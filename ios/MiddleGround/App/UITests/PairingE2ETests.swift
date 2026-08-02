import XCTest

/// Two-device end-to-end: pairing, live sync, and the reward loop against real Firebase.
///
/// Each test drives ONE simulator, so a full run invokes them in sequence across two
/// devices — see `Scripts/two-device-e2e.sh`. The invite code is handed between runs via
/// the `MG_INVITE_CODE` environment variable (xcodebuild forwards `TEST_RUNNER_`-prefixed
/// variables to the test process).
///
/// Requires: Email/Password enabled in Firebase Auth, and firestore rules + indexes deployed.
final class PairingE2ETests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(asTestUser label: String) {
        app.launchArguments = ["-MGTestUser", label]
        app.launch()
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Signs in with the deterministic DEBUG test account and walks onboarding up to the
    /// pairing step.
    ///
    /// Driven by whatever is currently on screen rather than a fixed step sequence: the test
    /// account pre-fills the name field, so its placeholder disappears and step order can't
    /// be assumed.
    private func signInAndReachPairing() throws {
        let testAccount = app.buttons["Use a test account"]
        guard testAccount.waitForExistence(timeout: 30) else {
            throw XCTSkip("Already signed in — reset the simulator to re-run onboarding")
        }
        testAccount.tap()

        let getStarted = app.buttons["Get Started"]
        let deadline = Date().addingTimeInterval(90)

        while Date() < deadline && !getStarted.exists {
            if app.buttons["Skip for now"].exists {
                app.buttons["Skip for now"].tap()
            } else if app.buttons["Continue"].exists {
                // Profile step. `Continue` is an exact-label match, so it cannot collide
                // with "Continue with Apple".
                let field = app.textFields.firstMatch
                if field.exists, (field.value as? String ?? "").isEmpty {
                    field.tap()
                    field.typeText("E2E Tester")
                }
                app.buttons["Continue"].tap()
            } else {
                Thread.sleep(forTimeInterval: 1)
            }
        }

        if !getStarted.exists { capture("e2e-stuck-in-onboarding") }
        XCTAssertTrue(
            getStarted.waitForExistence(timeout: 10),
            "Did not reach the relationship/pairing step. On screen:\n\(app.debugDescription)"
        )
    }

    // MARK: - Device A

    /// Creates the relationship and prints its invite code for the second device to consume.
    func testA1_createsRelationshipAndPublishesInviteCode() throws {
        launch(asTestUser: "A")
        try signInAndReachPairing()
        capture("e2e-A1-pairing-step")

        // "Invite someone" is the default segment; make it explicit.
        let inviteSegment = app.buttons["Invite someone"]
        if inviteSegment.exists { inviteSegment.tap() }
        app.buttons["Get Started"].tap()

        let code = app.staticTexts["inviteCode"]
        if !code.waitForExistence(timeout: 30) {
            capture("e2e-A2-no-invite-code")
            XCTFail("No invite code was shown after onboarding. On screen:\n\(app.debugDescription)")
            return
        }
        capture("e2e-A2-invite-code")

        let value = code.label.replacingOccurrences(of: " ", with: "")
        XCTAssertEqual(value.count, 6, "Invite code should be 6 characters, got '\(value)'")

        // Consumed by Scripts/two-device-e2e.sh, which greps this marker out of the test
        // log to hand the code to device B. stdout is the transport here, so print is the
        // right tool rather than a logger.
        // swiftlint:disable:next no_print
        print("MG_E2E_INVITE_CODE=\(value)")
        add(XCTAttachment(string: value))

        // Dismiss the done step and confirm we land in the app.
        app.buttons["Start using Middle Ground"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Did not enter the app")
    }

    // MARK: - Device B

    func testB1_joinsWithInviteCode() throws {
        let code = try XCTUnwrap(
            ProcessInfo.processInfo.environment["MG_INVITE_CODE"],
            "Set MG_INVITE_CODE (via TEST_RUNNER_MG_INVITE_CODE) from device A's run"
        )

        launch(asTestUser: "B")
        try signInAndReachPairing()

        app.buttons["I have a code"].tap()
        let field = app.textFields["Invite code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(code)
        capture("e2e-B1-code-entered")

        app.buttons["Get Started"].tap()

        // Joining lands on the done step; dismiss it to enter the app.
        let finish = app.buttons["Start using Middle Ground"]
        if !finish.waitForExistence(timeout: 30) {
            capture("e2e-B2-join-failed")
            XCTFail("Joining with the invite code failed. On screen:\n\(app.debugDescription)")
            return
        }
        finish.tap()

        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 30),
            "Joining with the invite code did not complete onboarding"
        )
        capture("e2e-B2-joined")
    }

    /// With a partner present, the compose picker must show their NAME, and sending must work.
    func testB2_createsRequestForTheirPartner() throws {
        launch(asTestUser: "B")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Expected to be signed in")

        app.buttons["Create new request or spontaneous invite"].tap()
        app.buttons["New Request"].tap()
        XCTAssertTrue(app.navigationBars["New Request"].waitForExistence(timeout: 15))

        // The unpaired guard must be gone now that A and B are paired.
        XCTAssertFalse(
            app.staticTexts["No one has joined yet"].exists,
            "Still shows the unpaired state after joining"
        )

        let title = app.textFields.firstMatch
        title.tap()
        title.typeText("E2E dinner test")
        capture("e2e-B3-compose")

        let send = app.buttons["Send request"]
        if !send.waitForExistence(timeout: 10) {
            capture("e2e-B3-no-send-button")
            XCTFail("No \"Send request\" button in the compose sheet. On screen:\n\(app.debugDescription)")
            return
        }
        XCTAssertTrue(send.isEnabled, "Send is disabled — recipient was not resolved")
        send.tap()
        XCTAssertTrue(
            app.staticTexts["E2E dinner test"].waitForExistence(timeout: 30),
            "Created request did not appear in the sender's feed"
        )
        capture("e2e-B4-sent")
    }

    // MARK: - Device A again

    /// The hardest thing to verify: the request arrives without any interaction, through the
    /// Firestore snapshot listener that was dead code until recently.
    func testA3_seesPartnersRequestLiveAndAccepts() throws {
        launch(asTestUser: "A")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Expected to be signed in")

        let incoming = app.staticTexts["E2E dinner test"]
        XCTAssertTrue(
            incoming.waitForExistence(timeout: 45),
            "Partner's request never arrived — live sync (observeRequests) is not working"
        )
        capture("e2e-A3-received-live")

        let accept = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Accept'")).firstMatch
        if accept.waitForExistence(timeout: 10) {
            accept.tap()
            // Accepting awards XP and shows the celebration overlay.
            let celebration = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'XP' OR label CONTAINS[c] 'accepted'")
            ).firstMatch
            XCTAssertTrue(celebration.waitForExistence(timeout: 15), "No reward feedback after accepting")
            capture("e2e-A4-accepted-xp")
        }
    }

    /// Gamification must reflect the accept: real XP, not the frozen level-1 default.
    func testA4_activitiesReflectTheAccept() throws {
        launch(asTestUser: "A")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        app.tabBars.buttons["Activities"].tap()

        XCTAssertTrue(app.staticTexts["Achievements"].waitForExistence(timeout: 20))
        capture("e2e-A5-activities")

        let xpEntry = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'XP'")).firstMatch
        XCTAssertTrue(xpEntry.exists, "Activity feed shows no XP — the reward write path did not run")
    }
}
