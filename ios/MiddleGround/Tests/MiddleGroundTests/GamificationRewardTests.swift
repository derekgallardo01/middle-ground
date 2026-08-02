import XCTest
@testable import MiddleGround

/// Covers the reward write path. Previously `save(stats:)` had no caller outside tests,
/// so XP, streaks and achievements were frozen for every real user.
final class GamificationRewardTests: XCTestCase {
    private var service: GamificationService!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let userID = "reward_user"

    override func setUp() {
        super.setUp()
        suiteName = "GamificationRewardTests.\(UUID().uuidString)"
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

    /// First day within the next week that is (or isn't) a weekend.
    private static func nextDay(matchingWeekend: Bool) -> Date? {
        let calendar = Calendar.current
        return (0..<7).lazy
            .compactMap { calendar.date(byAdding: .day, value: $0, to: Date()) }
            .first { calendar.isDateInWeekend($0) == matchingWeekend }
    }

    private func request(proposedTime: Date? = nil) -> Request {
        Request(
            creatorID: "someone",
            recipientIDs: [userID],
            category: .relationship,
            title: "Dinner?",
            proposedTime: proposedTime
        )
    }

    func testAcceptingAwardsXPAndPersistsIt() async {
        let outcome = await service.recordResponse(.accept, to: request(), for: userID)

        XCTAssertEqual(outcome.xpAwarded, 25)
        XCTAssertEqual(outcome.stats.relationshipXP, 25)
        XCTAssertEqual(outcome.stats.acceptedCount, 1)

        // The whole point: it survives a re-read.
        let reloaded = await service.stats(for: userID)
        XCTAssertEqual(reloaded.relationshipXP, 25)
        XCTAssertEqual(reloaded.acceptedCount, 1)
    }

    func testResponseTypesAwardDifferentXP() async {
        let accept = await service.recordResponse(.accept, to: request(), for: userID)
        XCTAssertEqual(accept.xpAwarded, 25)

        let negotiate = await service.recordResponse(.negotiate, to: request(), for: userID)
        XCTAssertEqual(negotiate.xpAwarded, 15)
        XCTAssertEqual(negotiate.stats.negotiatedCount, 1)

        let decline = await service.recordResponse(.decline, to: request(), for: userID)
        XCTAssertEqual(decline.xpAwarded, 5)

        XCTAssertEqual(decline.stats.relationshipXP, 45)
    }

    func testFirstResponseStartsStreakAndSameDayDoesNotDoubleCount() async {
        let first = await service.recordResponse(.accept, to: request(), for: userID)
        XCTAssertEqual(first.stats.streakDays, 1)
        XCTAssertTrue(first.streakExtended)

        let second = await service.recordResponse(.accept, to: request(), for: userID)
        XCTAssertEqual(second.stats.streakDays, 1, "two responses on the same day is still a 1-day streak")
        XCTAssertFalse(second.streakExtended)
    }

    func testLevelRisesWithXP() async {
        XCTAssertEqual(GamificationRules.level(forXP: 0), 1)
        XCTAssertEqual(GamificationRules.level(forXP: 499), 1)
        XCTAssertEqual(GamificationRules.level(forXP: 500), 2)
        XCTAssertEqual(GamificationRules.nextLevelXP(forXP: 500), 1000)

        // 20 accepts = 500 XP = level 2.
        for _ in 0..<20 {
            await service.recordResponse(.accept, to: request(), for: userID)
        }
        let stats = await service.stats(for: userID)
        XCTAssertEqual(stats.relationshipXP, 500)
        XCTAssertEqual(stats.level, 2)
    }

    func testNegotiatingTenTimesUnlocksGreatCommunicator() async {
        var unlocked: [Achievement] = []
        for _ in 0..<10 {
            unlocked += await service.recordResponse(.negotiate, to: request(), for: userID).newlyUnlocked
        }

        XCTAssertEqual(unlocked.map(\.id), ["ach_1"])

        let achievements = await service.achievements(for: userID)
        let greatCommunicator = achievements.first { $0.id == "ach_1" }
        XCTAssertEqual(greatCommunicator?.isUnlocked, true)
        XCTAssertEqual(achievements.first { $0.id == "ach_4" }?.isUnlocked, false, "50-count achievement stays locked")
    }

    func testWeekendAcceptsCountTowardWeekendWarrior() async throws {
        // Find a Saturday so the achievement matches its own description.
        let saturday = try XCTUnwrap(Self.nextDay(matchingWeekend: true), "a weekend exists within a week")

        for _ in 0..<5 {
            await service.recordResponse(.accept, to: request(proposedTime: saturday), for: userID)
        }
        let stats = await service.stats(for: userID)
        XCTAssertEqual(stats.weekendAcceptedCount, 5)

        let achievements = await service.achievements(for: userID)
        XCTAssertEqual(achievements.first { $0.id == "ach_2" }?.isUnlocked, true)
    }

    func testWeekdayAcceptsDoNotCountAsWeekend() async throws {
        let weekday = try XCTUnwrap(Self.nextDay(matchingWeekend: false), "a weekday exists within a week")

        await service.recordResponse(.accept, to: request(proposedTime: weekday), for: userID)

        let stats = await service.stats(for: userID)
        XCTAssertEqual(stats.acceptedCount, 1)
        XCTAssertEqual(stats.weekendAcceptedCount, 0)
    }

    func testRespondingAppendsToTheActivityFeed() async {
        await service.recordResponse(.accept, to: request(), for: userID)

        let activities = await service.activities(for: userID)
        XCTAssertTrue(activities.contains { $0.type == .xpEarned && $0.title == "+25 XP" })
        XCTAssertTrue(activities.contains { $0.type == .streakUpdate })
    }

    func testWeeklyCompletionMarksTodayAfterAResponse() async {
        let before = await service.weeklyCompletion(for: userID)
        XCTAssertEqual(before.count, 7)
        XCTAssertFalse(before.contains(true), "a new user has an empty week")

        await service.recordResponse(.accept, to: request(), for: userID)

        let after = await service.weeklyCompletion(for: userID)
        XCTAssertEqual(after.count, 7)
        XCTAssertTrue(after.contains(true), "today is marked complete")
    }

    func testStatsDecodeFromLegacyBlobWithoutCounterFields() throws {
        // Stats written before the counters existed must still decode.
        let legacy = Data("""
        {"streakDays":3,"relationshipXP":120,"level":1,"growthScore":40,"nextLevelXP":500}
        """.utf8)

        let stats = try JSONDecoder().decode(GamificationStats.self, from: legacy)

        XCTAssertEqual(stats.streakDays, 3)
        XCTAssertEqual(stats.relationshipXP, 120)
        XCTAssertEqual(stats.acceptedCount, 0)
        XCTAssertNil(stats.lastResponseDate)
    }
}
