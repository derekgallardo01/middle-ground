import XCTest
@testable import MiddleGround

/// Restoring progress onto a device that has none — and knowing when it failed.
///
/// The whole screen renders from a local store, so a device with nothing in it draws Level 1,
/// 0 XP and a 0-day streak. That is correct for a new person and a lie to everybody else, and
/// nothing distinguished the two: `try?` flattened "the server holds nothing" and "the server
/// could not be reached" into the same nil. Split out from `GamificationServiceTests`, which the
/// 400-line file limit had caught up with.
final class GamificationMirrorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let userID = "test_user"

    override func setUp() {
        super.setUp()
        suiteName = "GamificationMirrorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// A restore that couldn't reach the server must say so, and must be retried.
    ///
    /// The screen renders from the local store, so a failed restore leaves it showing Level 1,
    /// 0 XP and no achievements — indistinguishable from a brand-new account. Worse, the
    /// "already attempted" marker was set *before* the read, so coming back online changed
    /// nothing until the app was relaunched.
    func testAnUnreachableMirrorReportsUnavailableAndIsTriedAgain() async {
        let mirror = UnreachableGamificationRepository()
        let remote = GamificationStats(
            streakDays: 6, relationshipXP: 1200, level: 4, growthScore: 40, nextLevelXP: 1500
        )
        await mirror.save(remote, for: userID)
        await mirror.goOffline()

        let fresh = GamificationService(store: defaults, mirror: mirror)
        let firstAttempt = await fresh.restoreFromMirrorIfNeeded(for: userID)

        XCTAssertEqual(firstAttempt, .unavailable, "defaults must not be presented as progress")
        let duringOutage = await fresh.stats(for: userID)
        XCTAssertEqual(duringOutage.relationshipXP, 0, "there is genuinely nothing to show yet")

        await mirror.comeBackOnline()
        let secondAttempt = await fresh.restoreFromMirrorIfNeeded(for: userID)

        XCTAssertEqual(secondAttempt, .restored, "a failed attempt must not count as an attempt")
        let after = await fresh.stats(for: userID)
        XCTAssertEqual(after.relationshipXP, 1200)
        XCTAssertEqual(after.streakDays, 6)
    }

    /// The server was reached and holds nothing. Zeroes are the truth here, and saying
    /// "unavailable" would put an error in front of every new user's first visit.
    func testAnEmptyMirrorIsNotAnOutage() async {
        let mirror = MockGamificationRepository()
        let fresh = GamificationService(store: defaults, mirror: mirror)

        let outcome = await fresh.restoreFromMirrorIfNeeded(for: userID)

        XCTAssertEqual(outcome, .nothingStored)
    }
}

/// A mirror that can lose its connection, so the difference between "nothing stored" and
/// "couldn't ask" is testable — `MockGamificationRepository` can only ever succeed.
actor UnreachableGamificationRepository: GamificationRepository {
    private var storage: [String: GamificationStats] = [:]
    private var histories: [String: MirroredHistory] = [:]
    private var isReachable = true

    func goOffline() { isReachable = false }
    func comeBackOnline() { isReachable = true }

    private func requireNetwork() throws {
        guard isReachable else {
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }
    }

    func stats(for userID: String) async throws -> GamificationStats? {
        try requireNetwork()
        return storage[userID]
    }

    func save(_ stats: GamificationStats, for userID: String) async {
        storage[userID] = stats
    }

    func history(for userID: String) async throws -> MirroredHistory? {
        try requireNetwork()
        return histories[userID]
    }

    func save(_ history: MirroredHistory, for userID: String) async {
        histories[userID] = history
    }

    func allStats(limit: Int) async throws -> [String: GamificationStats] {
        try requireNetwork()
        return storage
    }
}
