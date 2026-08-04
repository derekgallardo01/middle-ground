import XCTest
@testable import MiddleGround

/// Shared availability, and the boundary it must not cross.
///
/// The feature only exists in a form the Privacy Policy can still describe honestly: a block is a
/// start and an end, authored by hand, with nothing read from the device calendar. The encoding
/// test is the one that matters — it is what stops a title or an event identifier being added
/// later without anybody noticing the promise had changed.
final class AvailabilityTests: XCTestCase {
    private let calendar = Calendar.current

    func testAWholeDayRunsMidnightToMidnight() {
        let block = UnavailableBlock.wholeDay(Date())
        XCTAssertTrue(block.isAllDay)
        XCTAssertEqual(block.end.timeIntervalSince(block.start), 86_400, accuracy: 3_600)
    }

    func testOverlapIsExclusiveAtTheEdges() {
        let start = Date()
        let block = UnavailableBlock(start: start, end: start.addingTimeInterval(3_600))

        XCTAssertTrue(block.overlaps(start.addingTimeInterval(1_800), start.addingTimeInterval(5_400)))
        XCTAssertFalse(
            block.overlaps(start.addingTimeInterval(3_600), start.addingTimeInterval(7_200)),
            "a plan starting exactly when a block ends does not clash"
        )
        XCTAssertFalse(
            block.overlaps(start.addingTimeInterval(-7_200), start),
            "a plan ending exactly when a block starts does not clash"
        )
    }

    func testCoversADayEvenWhenTheBlockIsPartial() {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let block = UnavailableBlock(start: noon, end: noon.addingTimeInterval(3_600))
        XCTAssertTrue(block.covers(Date()))
        XCTAssertFalse(block.covers(calendar.date(byAdding: .day, value: 1, to: Date())!))
    }

    func testBusyIsAnswerableForAWindowAndForADay() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let availability = SharedAvailability(userID: "user_2", blocks: [.wholeDay(tomorrow)])

        XCTAssertTrue(availability.isBusy(on: tomorrow))
        XCTAssertFalse(availability.isBusy(on: Date()))
        XCTAssertTrue(
            availability.isBusy(
                from: calendar.startOfDay(for: tomorrow).addingTimeInterval(3_600),
                to: calendar.startOfDay(for: tomorrow).addingTimeInterval(7_200)
            )
        )
    }

    /// The boundary. A block must carry times and nothing else — no title, no location, no event
    /// identifier — or the policy's "your events stay on your device" stops being true.
    func testABlockCarriesNothingButTimes() throws {
        let block = UnavailableBlock(start: Date(), end: Date().addingTimeInterval(3_600))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? [String: Any]
        )

        XCTAssertEqual(Set(json.keys), ["id", "start", "end", "isAllDay"])
        for forbidden in ["title", "location", "notes", "eventID", "calendarID", "url"] {
            XCTAssertNil(json[forbidden], "\(forbidden) must never be shared")
        }
    }

    func testSavingIsScopedToOneGroup() async throws {
        let repository = MockAvailabilityRepository(seed: [:])
        let mine = SharedAvailability(userID: "user_1", blocks: [.wholeDay(Date())])
        try await repository.save(mine, forGroup: "rel_1")

        let inGroup = try await repository.availability(forGroup: "rel_1")
        XCTAssertEqual(inGroup.count, 1)

        let elsewhere = try await repository.availability(forGroup: "rel_2")
        XCTAssertTrue(
            elsewhere.isEmpty,
            "blocking time for one group must not announce it to another"
        )
    }
}
