import XCTest
@testable import MiddleGround

/// The figures an operator makes decisions on.
///
/// Activation was paired groups over all groups — a share of *groups*, not of people — so somebody
/// who made three groups and paired none counted against it three times. Since the denominator was
/// never people, the number was never about them, and it is the one figure that answers whether
/// the product works at all.
final class AdminOverviewTests: XCTestCase {

    // MARK: - Activation is about people

    /// The case that made the old number wrong: one person, three groups, none paired.
    func testSomebodyWithSeveralUnpairedGroupsCountsOnce() {
        var overview = AdminOverview()
        overview.userCount = 1
        overview.relationshipCount = 3
        overview.pairedCount = 0
        overview.activatedUserCount = 0

        XCTAssertEqual(overview.activationRate, 0)
        // And the group figure still says its own true thing.
        XCTAssertEqual(overview.groupPairingRate, 0)
    }

    /// The mirror of it: one person, three groups, one paired. They are activated — they have
    /// somebody to plan with — even though two thirds of their groups are empty.
    func testOnePairedGroupIsEnoughToBeActivated() {
        var overview = AdminOverview()
        overview.userCount = 1
        overview.relationshipCount = 3
        overview.pairedCount = 1
        overview.activatedUserCount = 1

        XCTAssertEqual(overview.activationRate, 1.0, "a person with somebody to plan with is activated")
        XCTAssertEqual(overview.groupPairingRate, 1.0 / 3.0, accuracy: 0.001)
    }

    /// The two questions come apart, which is the reason both are shown.
    func testTheTwoRatesAnswerDifferentQuestions() {
        var overview = AdminOverview()
        overview.userCount = 10
        overview.activatedUserCount = 8
        overview.relationshipCount = 20
        overview.pairedCount = 5

        XCTAssertEqual(overview.activationRate, 0.8, accuracy: 0.001)
        XCTAssertEqual(overview.groupPairingRate, 0.25, accuracy: 0.001)
        XCTAssertNotEqual(overview.activationRate, overview.groupPairingRate)
    }

    /// No users is not zero percent activated — it is nothing to report. Dividing anyway would
    /// put a scary 0% on the panel of a product that has not launched.
    func testNoUsersReportsNothingRatherThanZero() {
        XCTAssertEqual(AdminOverview().activationRate, 0)
        XCTAssertEqual(AdminOverview().groupPairingRate, 0)
    }

    // MARK: - Active users say when they are a floor

    func testActiveCountsReadPlainlyWhenComplete() {
        var overview = AdminOverview()
        overview.dailyActiveUsers = 12
        overview.weeklyActiveUsers = 40

        XCTAssertEqual(overview.dailyActiveDisplay, "12")
        XCTAssertEqual(overview.weeklyActiveDisplay, "40")
    }

    /// Hitting the read ceiling must be visible. A number that is quietly a floor gets planned
    /// against as if it were the whole — the same reason `pairedCount` reports "N+".
    func testHittingTheCeilingIsSaidOutLoud() {
        var overview = AdminOverview()
        overview.dailyActiveUsers = 2_000
        overview.weeklyActiveUsers = 2_000
        overview.activeUserCountsAreExact = false

        XCTAssertEqual(overview.dailyActiveDisplay, "2000+")
        XCTAssertEqual(overview.weeklyActiveDisplay, "2000+")
    }
}
