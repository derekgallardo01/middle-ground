import XCTest
@testable import MiddleGround

final class GamificationServiceTests: XCTestCase {
    private var service: GamificationService!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let userID = "test_user"

    override func setUp() {
        super.setUp()
        // A per-test suite keeps runs independent; the previous version wrote to
        // UserDefaults.standard and only passed on a clean machine.
        suiteName = "GamificationServiceTests.\(UUID().uuidString)"
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

    func testDefaultStatsForNewUser() async {
        let stats = await service.stats(for: userID)

        XCTAssertEqual(stats.level, 1)
        XCTAssertEqual(stats.relationshipXP, 0)
        XCTAssertEqual(stats.streakDays, 0)
    }

    func testSaveAndLoadStats() async {
        var stats = await service.stats(for: userID)
        stats.relationshipXP = 100
        stats.level = 2
        await service.save(stats: stats, for: userID)

        let loaded = await service.stats(for: userID)
        XCTAssertEqual(loaded.relationshipXP, 100)
        XCTAssertEqual(loaded.level, 2)
    }

    func testDefaultAchievementsAreLocked() async {
        let achievements = await service.achievements(for: userID)

        XCTAssertFalse(achievements.isEmpty)
        XCTAssertTrue(achievements.allSatisfy { !$0.isUnlocked })
    }

    // MARK: - Per-category progression

    func testRespondingAwardsXPToTheRequestsOwnCategory() async {
        let travel = Request(
            creatorID: "partner",
            recipientIDs: [userID],
            category: .travel,
            title: "Weekend away"
        )
        let outcome = await service.recordResponse(.accept, to: travel, for: userID)

        XCTAssertEqual(outcome.stats.categoryXP["travel"], GamificationRules.xp(for: .accept))
        XCTAssertEqual(outcome.stats.level(for: .travel), 1)
        XCTAssertNil(outcome.stats.categoryXP["dating"], "other categories must be untouched")
    }

    /// A category this build cannot name should not accrue a level under a "?" icon.
    func testUnknownCategoryEarnsNoCategoryXP() async {
        let mystery = Request(
            creatorID: "partner",
            recipientIDs: [userID],
            category: .unknown,
            title: "???"
        )
        let outcome = await service.recordResponse(.accept, to: mystery, for: userID)

        XCTAssertTrue(outcome.stats.categoryXP.isEmpty)
        XCTAssertEqual(
            outcome.stats.relationshipXP,
            GamificationRules.xp(for: .accept),
            "overall XP is still awarded"
        )
    }

    func testRankedCategoriesHidesEmptyOnesAndOrdersByProgress() {
        let stats = GamificationStats(
            streakDays: 0,
            relationshipXP: 0,
            level: 1,
            growthScore: 0,
            nextLevelXP: 500,
            categoryXP: ["dating": 40, "travel": 900, "chill": 0]
        )

        XCTAssertEqual(stats.rankedCategories.map(\.category), [.travel, .dating])
        XCTAssertEqual(stats.level(for: .travel), 2)
        XCTAssertEqual(stats.level(for: .family), 1, "a category with no XP is still level 1")
    }

    /// The same class of failure as the unknown-category fallback: a blob written before the
    /// field existed must load rather than throw away everything alongside it.
    func testStatsWrittenBeforeCategoryXPExistedStillDecode() throws {
        let legacy = """
        {"streakDays":3,"relationshipXP":150,"level":1,"growthScore":12,"nextLevelXP":500}
        """

        let decoded = try JSONDecoder().decode(GamificationStats.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.relationshipXP, 150)
        XCTAssertTrue(decoded.categoryXP.isEmpty)
    }

    // MARK: - Goals

    /// Progress used to be a switch on hardcoded IDs ending in `default: 0`, so a goal added
    /// without editing that switch sat at zero forever. Each goal now carries its own metric.
    func testGoalsMeasureTheirOwnMetric() {
        let stats = GamificationStats(
            streakDays: 7,
            relationshipXP: 0,
            level: 1,
            growthScore: 0,
            nextLevelXP: 500,
            acceptedCount: 12,
            negotiatedCount: 4,
            weekendAcceptedCount: 2,
            categoryXP: ["dating": 260]
        )
        let goal = { (metric: GoalMetric, category: RequestCategory?) in
            Achievement(
                id: "g",
                title: "t",
                description: "d",
                iconName: "i",
                requiredValue: 1,
                metric: metric,
                category: category
            )
        }

        XCTAssertEqual(goal(.streakDays, nil).progress(in: stats), 7)
        XCTAssertEqual(goal(.accepted, nil).progress(in: stats), 12)
        XCTAssertEqual(goal(.negotiated, nil).progress(in: stats), 4)
        XCTAssertEqual(goal(.weekendAccepted, nil).progress(in: stats), 2)
        XCTAssertEqual(goal(.categoryXP, .dating).progress(in: stats), 260)
        XCTAssertEqual(goal(.categoryXP, .travel).progress(in: stats), 0)
        XCTAssertEqual(goal(.categoryXP, nil).progress(in: stats), 0, "unscoped category goal")
    }

    /// Achievements stored before goals carried a metric must keep measuring what they did.
    func testLegacyStoredAchievementsKeepTheirOriginalMetric() throws {
        let legacy = """
        [{"id":"ach_2","title":"Weekend Warrior","description":"d","iconName":"airplane",
          "requiredValue":5},
         {"id":"ach_3","title":"Streak Starter","description":"d","iconName":"flame.fill",
          "requiredValue":3}]
        """

        let decoded = try JSONDecoder().decode([Achievement].self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded[0].metric, .weekendAccepted)
        XCTAssertEqual(decoded[1].metric, .streakDays)
    }

    /// Goals added after someone started using the app must still reach them.
    func testNewGoalsAppearForUsersWhoAlreadyHaveStoredProgress() async {
        var existing = await service.achievements(for: userID)
        existing = [existing[0]]
        existing[0].unlockedAt = Date()
        await service.save(achievements: existing, for: userID)

        let merged = await service.achievements(for: userID)

        XCTAssertTrue(merged.contains { $0.id == "goal_dating" }, "goals added later must appear")
        XCTAssertTrue(
            merged.first { $0.id == existing[0].id }?.isUnlocked == true,
            "already-earned progress must survive the merge"
        )
    }

    // MARK: - Restoring from the mirror
    //
    // This is what a reinstall or a new phone looks like: the mirror holds the user's progress
    // and the local store is empty. It went unnoticed that nothing ever called the restore,
    // because nothing ever tested it.

    func testRestoreFromMirrorPopulatesAnEmptyDevice() async {
        let mirror = MockGamificationRepository()
        var remote = GamificationStats(streakDays: 6, relationshipXP: 1200, level: 4, growthScore: 40, nextLevelXP: 1500)
        remote.acceptedCount = 9
        await mirror.save(remote, for: userID)

        let fresh = GamificationService(store: defaults, mirror: mirror)
        await fresh.restoreFromMirrorIfNeeded(for: userID)

        let restored = await fresh.stats(for: userID)
        XCTAssertEqual(restored.relationshipXP, 1200)
        XCTAssertEqual(restored.streakDays, 6)
        XCTAssertEqual(restored.level, 4)
    }

    /// Local progress is the fast path and must win — restoring over it would roll the user
    /// back to whatever the last successful mirror write happened to contain.
    func testRestoreDoesNotOverwriteProgressAlreadyOnTheDevice() async {
        let mirror = MockGamificationRepository()
        await mirror.save(
            GamificationStats(streakDays: 1, relationshipXP: 10, level: 1, growthScore: 0, nextLevelXP: 500),
            for: userID
        )

        let fresh = GamificationService(store: defaults, mirror: mirror)
        var local = await fresh.stats(for: userID)
        local.relationshipXP = 999
        await fresh.save(stats: local, for: userID)

        await fresh.restoreFromMirrorIfNeeded(for: userID)

        let after = await fresh.stats(for: userID)
        XCTAssertEqual(after.relationshipXP, 999)
    }

    /// Responding on a fresh install must not wipe the account's history.
    ///
    /// `recordResponse` reads local progress and writes the result through to the mirror. After a
    /// reinstall the local store is empty, so without restoring first it would build on zeroes and
    /// that write would replace the real history in Firestore. This became reachable the moment
    /// Home stopped loading stats: responding from the feed no longer passes through any screen
    /// that restores.
    func testRecordResponseRestoresBeforeAwardingOnAFreshInstall() async {
        let mirror = MockGamificationRepository()
        // Responded yesterday, so today's response should extend the streak rather than restart
        // it — which is only possible if the restore happened.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        let existing = GamificationStats(
            streakDays: 4,
            relationshipXP: 800,
            level: 2,
            growthScore: 30,
            nextLevelXP: 1000,
            acceptedCount: 8,
            negotiatedCount: 3,
            lastResponseDate: yesterday
        )
        await mirror.save(existing, for: userID)

        // A brand-new device: nothing in the local store at all.
        let fresh = GamificationService(store: defaults, mirror: mirror)
        let outcome = await fresh.recordResponse(.accept, to: .preview, for: userID)

        XCTAssertEqual(outcome.stats.acceptedCount, 9, "should build on the restored 8, not on 0")
        XCTAssertEqual(outcome.stats.relationshipXP, 800 + GamificationRules.xp(for: .accept))
        XCTAssertEqual(outcome.stats.streakDays, 5, "the existing streak must extend, not restart")

        let persisted = try? await mirror.stats(for: userID)
        XCTAssertEqual(persisted?.acceptedCount, 9, "the mirror must not be reset to a fresh start")
    }

    /// Stats alone left a new device showing the numbers with nothing behind them: a level with
    /// no badges and no record of how it was reached.
    func testRestoreBringsBackAchievementsAndTheActivityFeedToo() async {
        let mirror = MockGamificationRepository()
        await mirror.save(
            GamificationStats(
                streakDays: 3,
                relationshipXP: 600,
                level: 2,
                growthScore: 20,
                nextLevelXP: 1000
            ),
            for: userID
        )
        var earned = Achievement(
            id: "ach_1",
            title: "Great Communicator",
            description: "d",
            iconName: "trophy.fill",
            requiredValue: 10,
            metric: .negotiated
        )
        earned.unlockedAt = Date()
        let logged = Activity(userID: userID, type: .xpEarned, title: "Accepted a plan", value: 25)
        await mirror.save(
            MirroredHistory(achievements: [earned], activities: [logged]),
            for: userID
        )

        let fresh = GamificationService(store: defaults, mirror: mirror)
        await fresh.restoreFromMirrorIfNeeded(for: userID)

        let restoredAchievements = await fresh.achievements(for: userID)
        let restoredActivities = await fresh.activities(for: userID)

        XCTAssertTrue(
            restoredAchievements.first { $0.id == "ach_1" }?.isUnlocked == true,
            "an earned badge must come back"
        )
        XCTAssertEqual(restoredActivities.count, 1, "the feed must come back")
        XCTAssertEqual(restoredActivities.first?.title, "Accepted a plan")
    }

    func testEarningAnAchievementMirrorsIt() async {
        let mirror = MockGamificationRepository()
        let service = GamificationService(store: defaults, mirror: mirror)

        let logged = Activity(userID: userID, type: .xpEarned, title: "Something", value: 5)
        await service.save(activities: [logged], for: userID)

        let mirrored = try? await mirror.history(for: userID)
        XCTAssertEqual(mirrored?.activities.count, 1, "the feed must reach the durable copy")
    }

    /// Callers restore on every load, so a user with no progress anywhere must not re-read the
    /// mirror each time — the local store stays empty, so the nil check alone never settles.
    func testRestoreConsultsTheMirrorOnlyOnce() async {
        let mirror = CountingGamificationRepository()
        let fresh = GamificationService(store: defaults, mirror: mirror)

        await fresh.restoreFromMirrorIfNeeded(for: userID)
        await fresh.restoreFromMirrorIfNeeded(for: userID)
        await fresh.restoreFromMirrorIfNeeded(for: userID)

        let reads = await mirror.reads
        XCTAssertEqual(reads, 1)
    }
}

/// Counts reads so the once-per-session guard is observable.
private actor CountingGamificationRepository: GamificationRepository {
    private(set) var reads = 0

    func stats(for userID: String) async throws -> GamificationStats? {
        reads += 1
        return nil
    }

    func save(_ stats: GamificationStats, for userID: String) async {}

    func history(for userID: String) async throws -> MirroredHistory? { nil }

    func save(_ history: MirroredHistory, for userID: String) async {}

    func allStats(limit: Int) async throws -> [String: GamificationStats] { [:] }
}
