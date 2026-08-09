import Factory
import XCTest
@testable import MiddleGround

/// What time a plan happens where it happens.
///
/// Every date in the app renders in the reader's zone, which is right for a dinner across town and
/// wrong the moment the plan is abroad: "dinner at 8" in Barcelona reads as 8pm to somebody in
/// Chicago, seven hours from when anybody eats. Most of these tests are about the plans that are
/// **not** abroad, because every plan that exists has no zone and none of them may change.
///
/// Times are pinned to a fixed instant rather than `Date()`, and the reader's zone is stated in
/// each case rather than inherited from whatever machine is running the suite — a test that passes
/// only in America/Los_Angeles is a test that fails in CI.
final class PlanTimeZoneTests: XCTestCase {

    // Building a view model without this resolves the real Firestore repositories, Firebase is not
    // configured, and the case dies with "freed pointer was not the last allocation" — a crash
    // rather than a failure, so the suite reports zero and stops partway.
    override func setUp() {
        super.setUp()
        AppConfiguration.useMockRepositories = true
        Container.shared.authService.register { MockAuthService() }
    }

    override func tearDown() {
        Container.shared.authService.reset()
        AppConfiguration.useMockRepositories = false
        super.tearDown()
    }

    /// 2027-01-15 19:00 UTC. January on purpose: it is standard time in both hemispheres' usual
    /// suspects, so nothing here depends on a daylight-saving guess.
    private let instant = Date(timeIntervalSince1970: 1_800_039_600)

    private func plan(zone: String?, nights: Double? = nil) -> Request {
        Request(
            creatorID: "user_1",
            recipientIDs: ["user_2"],
            category: .travel,
            title: "Barcelona",
            proposedTime: instant,
            endTime: nights.map { instant.addingTimeInterval($0 * 86_400) },
            timeZoneID: zone
        )
    }

    // MARK: - Every plan that exists is unchanged

    func testAPlanWithNoZoneRendersOnTheReadersClock() {
        let dinner = plan(zone: nil)

        XCTAssertFalse(dinner.isInAnotherTimeZone)
        XCTAssertEqual(dinner.displayTimeZone, .current)
        XCTAssertNil(dinner.timeZoneName)
        XCTAssertNil(dinner.localTimeSummary)
    }

    /// A zone identical to the reader's is not worth a word. "7:30 PM Eastern Time" under a date,
    /// to somebody in New York, is noise about a difference that does not exist.
    func testAPlanInTheReadersOwnZoneSaysNothing() {
        let local = plan(zone: TimeZone.current.identifier)

        XCTAssertFalse(local.isInAnotherTimeZone)
        XCTAssertNil(local.localTimeSummary)
    }

    /// Different names, same clock. Two zones can be the same hour, and naming one at the other is
    /// a distinction the reader cannot act on.
    func testTwoZonesOnTheSameClockAreNotAnotherTimeZone() throws {
        // Both are UTC in January. Chosen for that rather than for being interesting.
        let dublin = Request(
            creatorID: "u",
            recipientIDs: [],
            category: .travel,
            title: "t",
            proposedTime: instant,
            timeZoneID: "Europe/Dublin"
        )
        let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        XCTAssertEqual(
            london.secondsFromGMT(for: instant),
            try XCTUnwrap(dublin.timeZone).secondsFromGMT(for: instant),
            "the premise of this test no longer holds"
        )
    }

    /// A zone this device has never heard of must fall back, not crash and not half-apply.
    func testAnUnknownZoneFallsBackToTheReadersClock() {
        let nonsense = plan(zone: "Mars/Olympus_Mons")

        XCTAssertNil(nonsense.timeZone)
        XCTAssertFalse(nonsense.isInAnotherTimeZone)
        XCTAssertEqual(nonsense.displayTimeZone, .current)
    }

    func testAPlanWithAZoneButNoTimeHasNothingToSay() {
        var chore = plan(zone: "Europe/Madrid")
        chore.proposedTime = nil

        XCTAssertFalse(chore.isInAnotherTimeZone)
        XCTAssertNil(chore.localTimeSummary)
    }

    // MARK: - A plan abroad

    private func abroad(nights: Double? = nil) -> Request {
        // Somewhere that is not the same clock as any plausible CI machine or this one.
        plan(zone: "Asia/Tokyo", nights: nights)
    }

    func testAPlanAbroadKnowsItIsElsewhere() throws {
        let trip = abroad()
        try XCTSkipIf(
            TimeZone.current.secondsFromGMT(for: instant) == 9 * 3600,
            "this machine is on Tokyo time; there is no difference to test"
        )

        XCTAssertTrue(trip.isInAnotherTimeZone)
        XCTAssertEqual(trip.displayTimeZone.identifier, "Asia/Tokyo")
    }

    /// The sentence the whole field exists to produce. 19:00 UTC is 04:00 the next day in Tokyo,
    /// and that hour must be the one on screen.
    func testTheHourShownIsTheHourThere() throws {
        try XCTSkipIf(TimeZone.current.secondsFromGMT(for: instant) == 9 * 3600)
        let summary = try XCTUnwrap(abroad().localTimeSummary)

        XCTAssertTrue(
            summary.contains("4:00") || summary.contains("04:00"),
            "expected the Tokyo hour, got \(summary)"
        )
        XCTAssertFalse(summary.isEmpty)
    }

    /// And it has to say *which* clock, or it is an unattributed number that looks like a mistake.
    func testTheClockIsNamed() throws {
        try XCTSkipIf(TimeZone.current.secondsFromGMT(for: instant) == 9 * 3600)
        let name = try XCTUnwrap(abroad().timeZoneName)

        XCTAssertFalse(name.isEmpty)
        XCTAssertTrue(
            try XCTUnwrap(abroad().localTimeSummary).contains(name),
            "the hour is shown without saying whose clock it is"
        )
    }

    // MARK: - The date, not just the hour

    /// The failure that makes a zone worth storing at all: 19:00 UTC on the 15th is 04:00 on the
    /// **16th** in Tokyo. A card showing the 15th to somebody in London is showing a day that is
    /// not the day on the tickets.
    func testTheDateShownIsTheDateThere() throws {
        try XCTSkipIf(TimeZone.current.secondsFromGMT(for: instant) >= 9 * 3600)
        let there = try XCTUnwrap(abroad().dateSummary)
        let here = try XCTUnwrap(plan(zone: nil).dateSummary)

        XCTAssertNotEqual(there, here, "the plan's own date is being shown on the reader's clock")
        XCTAssertTrue(there.contains("16"), "expected the 16th in Tokyo, got \(there)")
    }

    /// A trip abroad still reads as a range, and the range is in the plan's zone at both ends.
    func testATripAbroadReadsAsARange() throws {
        let summary = try XCTUnwrap(abroad(nights: 4).dateSummary)

        XCTAssertTrue(summary.contains("–"), "a four-night trip rendered as a single date")
    }

    /// Four nights in Tokyo is four nights from wherever you read about it. Counting on the
    /// reader's calendar can put the boundary in a different place and report three.
    func testNightsAreCountedOnThePlansCalendar() {
        XCTAssertEqual(abroad(nights: 4).nightCount, 4)
        XCTAssertEqual(plan(zone: nil, nights: 4).nightCount, 4)
    }

    // MARK: - It has to survive the wire and the cache

    /// `name` was lost this way, then `seats`, then `endTime` was nearly lost the same way. The
    /// repository is remote-then-local, so a field the entity drops is invisible everywhere.
    func testTheZoneSurvivesTheOfflineCache() throws {
        let restored = try XCTUnwrap(RequestEntity(from: abroad(nights: 4)).toModel())

        XCTAssertEqual(restored.timeZoneID, "Asia/Tokyo", "the cache dropped the plan's clock")
    }

    /// `update(from:)` is a separate path from `init(from:)` and has forgotten a field before.
    func testUpdatingACachedPlanKeepsTheZone() throws {
        let entity = RequestEntity(from: plan(zone: nil))

        entity.update(from: abroad())

        XCTAssertEqual(try XCTUnwrap(entity.toModel()).timeZoneID, "Asia/Tokyo")
    }

    func testAPlanCachedBeforeZonesExistedStillLoads() throws {
        let entity = RequestEntity(from: abroad())
        entity.timeZoneID = nil

        let restored = try XCTUnwrap(entity.toModel())

        XCTAssertNil(restored.timeZoneID)
        XCTAssertFalse(restored.isInAnotherTimeZone)
    }

    /// The wire format is the other half of it — a DTO that drops the field means it never reaches
    /// anybody else's device even when this one shows it correctly.
    func testTheZoneSurvivesTheWire() throws {
        let dto = RequestDTO(from: abroad(nights: 4))

        XCTAssertEqual(dto.timeZoneID, "Asia/Tokyo")
        XCTAssertEqual(try XCTUnwrap(dto.toModel()).timeZoneID, "Asia/Tokyo")
    }

    /// Documents written before this shipped carry no such field and must decode unchanged.
    func testAPlanWrittenBeforeZonesExistedDecodes() throws {
        let json = """
        {"id":"r1","creatorID":"u1","recipientIDs":["u2"],"category":"daily","title":"Dinner",
         "status":"pending","negotiationChain":[],"confirmations":{},
         "createdAt":0,"updatedAt":0}
        """
        let decoder = JSONDecoder()

        let request = try decoder.decode(Request.self, from: Data(json.utf8))

        XCTAssertNil(request.timeZoneID)
        XCTAssertFalse(request.isInAnotherTimeZone)
    }

    // MARK: - What compose is allowed to stamp on a plan

    private func place(named name: String, zone: String?) -> DiscoveredPlace {
        DiscoveredPlace(
            id: "p1",
            name: name,
            category: nil,
            address: nil,
            latitude: 41.38,
            longitude: 2.16,
            distanceMiles: nil,
            phone: nil,
            website: nil,
            timeZoneIdentifier: zone
        )
    }

    @MainActor
    func testChoosingAPlaceAbroadStampsItsZone() {
        let viewModel = CreateRequestViewModel()

        viewModel.choose(place(named: "Bar Cañete", zone: "Europe/Madrid"))

        XCTAssertEqual(viewModel.placeTimeZoneID, "Europe/Madrid")
    }

    /// `chosenPlace` is never cleared. Pick a restaurant in Barcelona, change your mind and type
    /// over the field, and the plan would go out as "Joe's Diner" stamped `Europe/Madrid` — every
    /// date on it rendering an hour nobody meant, confidently and invisibly.
    @MainActor
    func testTypingOverAChosenPlaceDropsItsZone() {
        let viewModel = CreateRequestViewModel()
        viewModel.choose(place(named: "Bar Cañete", zone: "Europe/Madrid"))

        viewModel.location = "Joe's Diner"

        XCTAssertNil(viewModel.placeTimeZoneID, "a stale place stamped the wrong clock on a plan")
    }

    /// Apple does not always know. Nothing to record is not a failure — it is the old behaviour.
    @MainActor
    func testAPlaceWithNoKnownZoneStampsNothing() {
        let viewModel = CreateRequestViewModel()

        viewModel.choose(place(named: "Somewhere", zone: nil))

        XCTAssertNil(viewModel.placeTimeZoneID)
    }

    @MainActor
    func testAPlanWithNoPlaceAtAllStampsNothing() {
        XCTAssertNil(CreateRequestViewModel().placeTimeZoneID)
    }
}
