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

    func allStats(limit: Int) async throws -> [String: GamificationStats] { [:] }
}
