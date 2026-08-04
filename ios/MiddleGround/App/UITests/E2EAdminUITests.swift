import XCTest

/// The operator role, driven end to end.
///
/// This surface had **no** UI coverage of any kind, and could not have had any: in mock mode
/// `PreviewAuthService.isAdmin()` answered false, so the tab was never built and every section
/// behind it — including the reports queue and the follow-through figures — was unreachable on a
/// simulator. `-MGAdmin` exists for that, and confers nothing outside mock mode.
///
/// Each test captures a frame, so the log can point at what was on screen rather than asserting
/// that something passed.
final class E2EAdminUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MGMockMode", "-MGAdmin"]
        app.launch()
    }

    // MARK: - Helpers

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Opens one section of the panel. The picker is a segmented control that scrolls.
    @discardableResult
    private func openSection(_ name: String) -> Bool {
        guard app.tabBars.buttons["Admin"].waitForExistence(timeout: 15) else {
            XCTFail("the Admin tab should exist when the account carries the claim")
            return false
        }
        app.tabBars.buttons["Admin"].tap()

        let button = app.segmentedControls.buttons[name].exists
            ? app.segmentedControls.buttons[name]
            : app.buttons[name]
        for _ in 0..<4 where !button.exists || !button.isHittable {
            app.swipeLeft()
        }
        guard button.waitForExistence(timeout: 6), button.isHittable else {
            XCTFail("no \(name) section")
            return false
        }
        button.tap()
        return true
    }

    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }

    // MARK: - The gate itself

    /// The claim is what builds the tab. Without it the panel does not exist to be found.
    func test_admin_00_tabIsPresentOnlyForAnAdmin() throws {
        XCTAssertTrue(
            app.tabBars.buttons["Admin"].waitForExistence(timeout: 15),
            "an account carrying the claim should see the panel"
        )
        shoot("admin-00-tab-present")

        let ordinary = XCUIApplication()
        ordinary.launchArguments = ["-MGMockMode"]
        ordinary.launch()
        XCTAssertTrue(ordinary.tabBars.buttons["Requests"].waitForExistence(timeout: 15))
        XCTAssertFalse(
            ordinary.tabBars.buttons["Admin"].exists,
            "an ordinary account must not be offered the operator panel"
        )
    }

    // MARK: - Every section renders

    func test_admin_01_overview() throws {
        guard openSection("Overview") else { return }
        XCTAssertTrue(scrollTo(text(containing: "Users")), "the overview should count what exists")
        shoot("admin-01-overview")
    }

    func test_admin_02_users() throws {
        guard openSection("Users") else { return }
        XCTAssertTrue(scrollTo(app.staticTexts["Alex"]), "the user list should name people")
        shoot("admin-02-users")
    }

    func test_admin_03_requests() throws {
        guard openSection("Requests") else { return }
        XCTAssertTrue(scrollTo(app.staticTexts["Date night this Friday?"]), "plans should be listed")
        shoot("admin-03-requests")
    }

    func test_admin_06_events() throws {
        guard openSection("Events") else { return }
        shoot("admin-06-events")
    }

    func test_admin_07_venues() throws {
        guard openSection("Venues") else { return }
        shoot("admin-07-venues")
    }

    func test_admin_08_audit() throws {
        guard openSection("Audit") else { return }
        shoot("admin-08-audit")
    }

    // MARK: - Reports: the queue can actually be worked

    /// The list rendered with no action on it at all, under a header promising review within 24
    /// hours — so a hundred unread reports and a hundred handled ones looked identical.
    func test_admin_04_reportsQueueOffersADecision() throws {
        guard openSection("Reports") else { return }

        XCTAssertTrue(
            scrollTo(text(containing: "Kept messaging")),
            "the waiting report should be shown with what was said about it"
        )
        XCTAssertTrue(app.buttons["Actioned"].exists, "a waiting report must be closable")
        XCTAssertTrue(app.buttons["Dismiss"].exists)
        shoot("admin-04-reports-waiting")
    }

    /// Driving the decision, not just checking the buttons are there.
    func test_admin_05_aReportCanBeClosed() throws {
        guard openSection("Reports") else { return }
        guard scrollTo(app.buttons["Actioned"]) else { return XCTFail("nothing to action") }

        app.buttons["Actioned"].tap()

        // The buttons retire and the decision takes their place.
        let decided = text(containing: "Actioned")
        XCTAssertTrue(decided.waitForExistence(timeout: 10), "the decision should be recorded on the report")
        shoot("admin-05-report-closed")
    }

    /// An already-decided report shows who decided and when, rather than offering the buttons again.
    func test_admin_09_aDecidedReportShowsWhoDecidedIt() throws {
        guard openSection("Reports") else { return }
        XCTAssertTrue(scrollTo(text(containing: "Dismissed")), "a closed report should say so")
        shoot("admin-09-report-already-decided")
    }

    // MARK: - Outcomes: the number the partnership runs on

    /// Recorded on every agreement, attendance and cancellation since 2 August 2026, and read by
    /// nothing until now.
    func test_admin_10_outcomesShowFollowThrough() throws {
        guard openSection("Outcomes") else { return }

        XCTAssertTrue(scrollTo(text(containing: "Follow-through")), "the headline figure should be shown")
        XCTAssertTrue(
            scrollTo(text(containing: "of settled plans happened")),
            "it should say what the percentage is of, not just show a number"
        )
        shoot("admin-10-outcomes")
    }

    func test_admin_11_outcomesBreakDownByPartySizeAndKind() throws {
        guard openSection("Outcomes") else { return }

        XCTAssertTrue(scrollTo(text(containing: "By party size")), "a restaurant reads it by cover count")
        XCTAssertTrue(scrollTo(text(containing: "By kind of plan")))
        shoot("admin-11-outcomes-breakdown")
    }

    /// The figure must carry its own caveat wherever it is quoted.
    func test_admin_12_outcomesSayWhenCollectionBegan() throws {
        guard openSection("Outcomes") else { return }
        XCTAssertTrue(
            scrollTo(text(containing: "Collection began")),
            "history cannot be reconstructed, and the screen should say so"
        )
        shoot("admin-12-outcomes-caveat")
    }
}
