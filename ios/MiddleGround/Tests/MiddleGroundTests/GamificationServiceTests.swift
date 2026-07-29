import XCTest
@testable import MiddleGround

final class GamificationServiceTests: XCTestCase {
    private var service: GamificationService!
    private let userID = "test_user"
    
    override func setUp() {
        super.setUp()
        service = GamificationService()
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
    }
    
    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
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
