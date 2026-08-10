import XCTest

/// The seam between the app and the backend, tested repeatably.
///
/// Every other UI suite runs under `-MGMockMode`, which swaps in in-memory repositories. That
/// proves the screen works and nothing else: no Firestore, no security rules, no Cloud Function.
/// An audit found five features with passing mock-mode tests and **zero documents ever written in
/// production** — a green suite and an unused feature are indistinguishable from inside the repo.
///
/// `firestore.rules` is already well tested, but against documents the *test* writes. This is the
/// other half: the documents the **app** writes, through the same rules. The two can diverge
/// silently — a repository that omits a field the rules require fails only at runtime, for a real
/// person, on a feature nobody has used yet.
///
/// Requires the emulators:
///
///     firebase emulators:start --only firestore,auth --project middle-ground-8fd13
///
/// Data is disposable and local, so these can run in CI and cannot touch production.
final class EmulatorSeamTests: XCTestCase {
    private var app: XCUIApplication!

    private static let projectID = "middle-ground-8fd13"
    private static let firestoreHost = "http://127.0.0.1:8080"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try skipUnlessEmulatorIsRunning()
        app = XCUIApplication()
        app.launchArguments = ["-MGUseEmulator", "-MGTestUser", "Seam"]
    }

    /// Skips rather than fails when the emulator is not up.
    ///
    /// A failure here would say "the app is broken" when the truth is "nothing was listening",
    /// and that is exactly the kind of misleading red that teaches people to ignore a suite.
    private func skipUnlessEmulatorIsRunning() throws {
        guard let url = URL(string: "\(Self.firestoreHost)/") else {
            throw XCTSkip("emulator host is not a valid URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        let reachable = XCTestExpectation(description: "emulator probe")
        var isUp = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            isUp = response != nil
            reachable.fulfill()
        }.resume()
        _ = XCTWaiter().wait(for: [reachable], timeout: 5)

        if !isUp {
            throw XCTSkip("Firestore emulator is not running — `firebase emulators:start`")
        }
    }

    /// Reads a collection straight out of the emulator. No auth: the emulator serves its REST API
    /// unauthenticated, which is what lets the test check the *result* of the app's write rather
    /// than only what the screen says about it.
    private func documentCount(inCollection path: String) -> Int {
        let endpoint = "\(Self.firestoreHost)/v1/projects/\(Self.projectID)"
            + "/databases/(default)/documents/\(path)"
        guard let url = URL(string: endpoint) else {
            XCTFail("could not build a URL for \(path)")
            return 0
        }
        let done = XCTestExpectation(description: "read \(path)")
        var count = 0

        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { done.fulfill() }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let documents = json["documents"] as? [[String: Any]] else { return }
            count = documents.count
        }.resume()

        _ = XCTWaiter().wait(for: [done], timeout: 15)
        return count
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The app has to reach Firestore at all before any feature test means anything.
    ///
    /// This is deliberately the first test: if the emulator wiring is wrong, everything below
    /// fails for a reason that has nothing to do with the features being checked.
    func testSeam0_theAppTalksToTheEmulatorRatherThanProduction() throws {
        app.launch()

        let signedIn = app.tabBars.firstMatch.waitForExistence(timeout: 60)
        let onboarding = app.buttons["Use a test account"].exists
        capture("seam-0-launched")

        XCTAssertTrue(
            signedIn || onboarding,
            "the app did not reach a usable state against the emulator. On screen:\n\(app.debugDescription)"
        )
    }

    /// Writing a user profile is the first thing the app does through the rules, so it is the
    /// cheapest proof that the app's document shape is one the rules accept.
    func testSeam1_signingInWritesAProfileTheRulesAccept() throws {
        app.launch()

        let testAccount = app.buttons["Use a test account"]
        if testAccount.waitForExistence(timeout: 45) {
            testAccount.tap()
        }

        // Onboarding is driven by whatever is on screen, as in PairingE2ETests — the test account
        // pre-fills the name, so step order cannot be assumed.
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline && !app.tabBars.firstMatch.exists && !app.buttons["Get Started"].exists {
            if app.buttons["Skip for now"].exists {
                app.buttons["Skip for now"].tap()
            } else if app.buttons["Continue"].exists {
                app.buttons["Continue"].tap()
            } else {
                Thread.sleep(forTimeInterval: 1)
            }
        }
        capture("seam-1-onboarded")

        XCTAssertGreaterThan(
            documentCount(inCollection: "users"),
            0,
            "no user document reached the emulator — the write or the rules refused it"
        )
    }
}
