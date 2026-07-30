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
}
