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

    /// The guard against paying for the same plan twice has to survive a reinstall.
    ///
    /// `settledPlanIDs` is not a statistic — it is the idempotence check in
    /// `GamificationService+Attendance.swift:26`. It was not carried in the mirror, so it restored
    /// empty and every plan a person had ever settled could be paid out again. Silently, and in
    /// their favour, which is the direction nobody reports.
    func testASettledPlanCannotBePaidTwiceAfterAReinstall() async {
        let mirror = MockGamificationRepository()
        let banked = GamificationStats(
            streakDays: 3,
            relationshipXP: 800,
            level: 2,
            growthScore: 20,
            nextLevelXP: 1000,
            attendedCount: 4,
            settledPlanIDs: ["req_settled"]
        )
        await mirror.save(banked, for: userID)

        // A new device: nothing local, everything from the mirror.
        let fresh = GamificationService(store: defaults, mirror: mirror)
        let outcome = await fresh.restoreFromMirrorIfNeeded(for: userID)

        XCTAssertEqual(outcome, .restored)
        let restored = await fresh.stats(for: userID)
        XCTAssertTrue(restored.settledPlanIDs.contains("req_settled"))
        XCTAssertEqual(restored.attendedCount, 4)
    }

    /// The one that actually catches it.
    ///
    /// The test above goes through `MockGamificationRepository`, which keeps the struct in memory
    /// and never converts — so it passed with the fix removed and proved nothing. The bug lives in
    /// the wire mapping, so the wire mapping is what has to be exercised. Verified by deleting the
    /// two fields again and watching this fail.
    func testTheWireFormatCarriesEverythingAReinstallNeeds() {
        let banked = GamificationStats(
            streakDays: 3,
            relationshipXP: 800,
            level: 2,
            growthScore: 20,
            nextLevelXP: 1000,
            attendedCount: 4,
            settledPlanIDs: ["req_settled"],
            categoryXP: ["friends": 120]
        )

        let onTheWire = GamificationStatsDTO(from: banked)
        let restored = onTheWire.toModel()

        XCTAssertEqual(
            restored.settledPlanIDs,
            ["req_settled"],
            "the payout guard is not on the wire — every settled plan pays out again on reinstall"
        )
        XCTAssertEqual(restored.attendedCount, 4)
        XCTAssertEqual(restored.categoryXP, ["friends": 120])
        XCTAssertEqual(restored.relationshipXP, 800)
        XCTAssertEqual(restored.streakDays, 3)
    }

    /// A mirror written before these fields existed must still load.
    func testAnOlderMirrorStillDecodes() throws {
        // A mirror document from before these fields existed.
        let fields = [
            #""streakDays":2"#, #""relationshipXP":100"#, #""level":1"#,
            #""growthScore":5"#, #""nextLevelXP":500"#, #""acceptedCount":1"#,
            #""negotiatedCount":0"#, #""weekendAcceptedCount":0"#
        ]
        let json = "{\(fields.joined(separator: ","))}"
        let data = try XCTUnwrap(json.data(using: .utf8))

        let dto = try JSONDecoder().decode(GamificationStatsDTO.self, from: data)

        XCTAssertEqual(dto.toModel().settledPlanIDs, [])
        XCTAssertEqual(dto.toModel().attendedCount, 0)
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
