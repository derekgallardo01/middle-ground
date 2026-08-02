import XCTest

/// Walkthrough against the **real** Firebase backend (no `-MGMockMode`).
///
/// Separate from `WalkthroughUITests` because these depend on deployed Firestore rules,
/// network, and a signed-in Apple ID — they are not hermetic and are not part of the
/// default CI gate.
final class RealBackendUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Deliberately no -MGMockMode: this must exercise Firebase for real.
        app.launch()
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Proves the app boots against real Firebase and reaches onboarding rather than
    /// aborting in `FirebaseApp.configure()`.
    func testLaunchesAgainstRealFirebase() {
        let appleButton = app.buttons["Continue with Apple"]
        let alreadySignedIn = app.tabBars.firstMatch

        let reachedSomething = appleButton.waitForExistence(timeout: 30)
            || alreadySignedIn.waitForExistence(timeout: 5)

        XCTAssertTrue(reachedSomething, "App did not reach onboarding or the main UI")
        capture("real-01-launch")
    }

    /// Taps Sign in with Apple and reports what the system presents. Diagnostic: tells us
    /// whether the simulator has an Apple ID available before we attempt a full pairing run.
    func testSignInWithAppleReachesSystemSheet() throws {
        let appleButton = app.buttons["Continue with Apple"]
        guard appleButton.waitForExistence(timeout: 30) else {
            throw XCTSkip("Already signed in — sign out first to exercise this path")
        }

        appleButton.tap()

        // The Apple auth sheet is owned by another process.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let authSheet = springboard.otherElements["ASAuthorizationRemoteViewController"]
        let continueButton = springboard.buttons["Continue"]
        let signInPrompt = springboard.staticTexts
            .containing(NSPredicate(format: "label CONTAINS[c] 'Apple'")).firstMatch

        let appeared = authSheet.waitForExistence(timeout: 15)
            || continueButton.waitForExistence(timeout: 5)
            || signInPrompt.waitForExistence(timeout: 5)

        capture("real-02-apple-sheet")

        // An error alert inside our app means the simulator has no usable Apple ID.
        let errorAlert = app.alerts["Oops"]
        if errorAlert.waitForExistence(timeout: 3) {
            let message = errorAlert.staticTexts.element(boundBy: 1).label
            capture("real-02-apple-error")
            throw XCTSkip("Sign in with Apple unavailable on this simulator: \(message)")
        }

        XCTAssertTrue(appeared, "Sign in with Apple did not present a system sheet")
    }
}
