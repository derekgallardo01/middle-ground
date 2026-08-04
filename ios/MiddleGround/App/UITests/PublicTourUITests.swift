import XCTest

/// The same tour, recorded for people outside the company.
///
/// No operator claim, so the Admin tab is absent from the panel *and* from the tab bar in every
/// frame. Trimming the admin section off the end of the full recording does not achieve that,
/// which is the whole reason this exists:
///
///     bash Scripts/full-tour.sh ~/Desktop/MiddleGround-Tour-Public --public
///
/// A subclass rather than a launch environment variable because `TEST_RUNNER_`-prefixed settings
/// did not reach the runner under `test-without-building`, and the failure mode was silent — a
/// seven-minute recording that looked right until the tab bar was examined.
final class PublicTourUITests: FullTourUITests {
    override var isPublicTour: Bool { true }
}
