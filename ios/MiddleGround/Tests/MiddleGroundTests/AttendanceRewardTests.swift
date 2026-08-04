import XCTest
@testable import MiddleGround

/// Paying out a plan that actually happened, and settling whatever was staked on it.
///
/// Both halves shipped inert. `stakeOutcome(for:)` was written and tested in isolation and never
/// applied to anybody's points, so the card said "you each get 25 back" and nothing moved. And
/// `confirmAttendance` never touched the reward loop at all: accepting a plan paid 25, declining
/// one paid 5, and turning up paid nothing — in an app whose whole claim is that turning up is
/// the point. These tests cover the payment, not the arithmetic; `StakeTests` covers the
/// arithmetic and passed the entire time it was unused.
final class AttendanceRewardTests: XCTestCase {
    private var service: GamificationService!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let userID = "me"

    override func setUp() {
        super.setUp()
        suiteName = "AttendanceRewardTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        service = GamificationService(store: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        service = nil
        super.tearDown()
    }

    private func plan(
        id: String = "req_settle",
        confirmations: [String: ConfirmationOutcome],
        stake: Int? = nil,
        stakeAccepted: Bool = true
    ) -> Request {
        var request = Request(
            id: id,
            creatorID: userID,
            recipientIDs: ["them"],
            category: .daily,
            title: "Plan",
            proposedTime: Date().addingTimeInterval(-3600),
            status: .accepted,
            confirmations: confirmations
        )
        if let stake {
            request.stake = Stake(proposedBy: userID, points: stake, acceptedBy: stakeAccepted ? "them" : nil)
        }
        return request
    }

    // MARK: - Turning up

    func testTurningUpPaysMoreThanAgreeingTo() {
        XCTAssertGreaterThan(
            GamificationRules.attendedXP,
            GamificationRules.xp(for: .accept),
            "the app tells people turning up is the point; the numbers have to agree with it"
        )
        XCTAssertGreaterThan(GamificationRules.attendedXP, GamificationRules.xp(for: .decline))
    }

    func testAPlanThatHappenedPaysForTurningUp() async {
        let request = plan(confirmations: [userID: .happened, "them": .happened])

        let outcome = await service.recordAttendance(of: request, for: userID)

        XCTAssertEqual(outcome?.xpAwarded, GamificationRules.attendedXP)
        let stats = await service.stats(for: userID)
        XCTAssertEqual(stats.relationshipXP, GamificationRules.attendedXP)
        XCTAssertEqual(stats.attendedCount, 1)
    }

    /// A plan falling through is not itself punished — only a stake takes points away.
    func testAPlanThatDidNotHappenPaysNothingAndCostsNothing() async {
        let request = plan(confirmations: [userID: .didNotHappen, "them": .didNotHappen])

        let outcome = await service.recordAttendance(of: request, for: userID)

        XCTAssertEqual(outcome?.xpAwarded, 0)
        let stats = await service.stats(for: userID)
        XCTAssertEqual(stats.relationshipXP, 0)
        XCTAssertEqual(stats.attendedCount, 0, "a plan that fell through is not one you turned up to")
    }

    func testNothingIsPaidUntilEveryoneHasAnswered() async {
        let request = plan(confirmations: [userID: .happened])

        let outcome = await service.recordAttendance(of: request, for: userID)

        XCTAssertNil(outcome, "one answer is not a settlement")
        let stats = await service.stats(for: userID)
        XCTAssertEqual(stats.relationshipXP, 0)
    }

    func testSomeoneNotOnThePlanIsNotPaid() async {
        let request = plan(confirmations: [userID: .happened, "them": .happened])

        let outcome = await service.recordAttendance(of: request, for: "stranger")

        XCTAssertNil(outcome)
    }

    // MARK: - The stake

    func testTurningUpWithAStakeReturnsItAsABonus() async {
        let request = plan(confirmations: [userID: .happened, "them": .happened], stake: 25)

        let outcome = await service.recordAttendance(of: request, for: userID)

        XCTAssertEqual(outcome?.xpAwarded, GamificationRules.attendedXP + 25)
    }

    func testAPlanThatFellThroughCostsTheStake() async {
        await service.save(stats: GamificationStats(
            streakDays: 0, relationshipXP: 100, level: 1, growthScore: 0, nextLevelXP: 500
        ), for: userID)

        let request = plan(confirmations: [userID: .didNotHappen, "them": .didNotHappen], stake: 25)
        let outcome = await service.recordAttendance(of: request, for: userID)

        XCTAssertEqual(outcome?.xpAwarded, -25)
        let stats = await service.stats(for: userID)
        XCTAssertEqual(stats.relationshipXP, 75)
    }

    /// Disagreement pays nobody — the same rule `stakeSettlement` already encodes.
    func testADisputedPlanSettlesTheStakeForNobody() async {
        let request = plan(confirmations: [userID: .happened, "them": .didNotHappen], stake: 25)

        let outcome = await service.recordAttendance(of: request, for: userID)

        XCTAssertEqual(outcome?.xpAwarded, 0, "one person saying it happened is not proof that it did")
    }

    /// A losing stake can cost you what you have and no more. Negative XP would mean a level
    /// below one and a progress bar reading backwards.
    func testXPCannotGoNegative() async {
        await service.save(stats: GamificationStats(
            streakDays: 0, relationshipXP: 10, level: 1, growthScore: 0, nextLevelXP: 500
        ), for: userID)

        let request = plan(confirmations: [userID: .didNotHappen, "them": .didNotHappen], stake: 100)
        await service.recordAttendance(of: request, for: userID)

        let stats = await service.stats(for: userID)
        XCTAssertEqual(stats.relationshipXP, 0)
        XCTAssertGreaterThanOrEqual(stats.level, 1)
    }

    // MARK: - Paying once

    /// The reason the ledger exists. Settlement is one event shared by several people, but each
    /// device pays only its own user — so this is called on confirming *and* on opening the plan,
    /// and whoever answered first is paid on their next visit rather than never.
    func testAPlanIsOnlyEverPaidOnce() async {
        let request = plan(confirmations: [userID: .happened, "them": .happened], stake: 25)

        let first = await service.recordAttendance(of: request, for: userID)
        let second = await service.recordAttendance(of: request, for: userID)
        let third = await service.recordAttendance(of: request, for: userID)

        XCTAssertEqual(first?.xpAwarded, GamificationRules.attendedXP + 25)
        XCTAssertNil(second, "a settled plan pays once")
        XCTAssertNil(third)

        let stats = await service.stats(for: userID)
        XCTAssertEqual(stats.relationshipXP, GamificationRules.attendedXP + 25)
        XCTAssertEqual(stats.attendedCount, 1)
    }

    func testTwoDifferentPlansAreBothPaid() async {
        let one = plan(id: "req_a", confirmations: [userID: .happened, "them": .happened])
        let two = plan(id: "req_b", confirmations: [userID: .happened, "them": .happened])

        await service.recordAttendance(of: one, for: userID)
        await service.recordAttendance(of: two, for: userID)

        let stats = await service.stats(for: userID)
        XCTAssertEqual(stats.relationshipXP, GamificationRules.attendedXP * 2)
        XCTAssertEqual(stats.attendedCount, 2)
    }
}
