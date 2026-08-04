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
}
