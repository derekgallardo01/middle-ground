import XCTest
@testable import MiddleGround

/// Who has blocked out the day being chosen — and, just as importantly, who has not said.
final class GroupBusyDayTests: XCTestCase {
    private let day = Date()
    private let names = ["them": "Sam", "third": "Priya"]

    private func blocked(_ userID: String, on day: Date) -> SharedAvailability {
        SharedAvailability(userID: userID, blocks: [.wholeDay(day)])
    }

    private func free(_ userID: String) -> SharedAvailability {
        SharedAvailability(userID: userID, blocks: [])
    }

    func testNamesWhoIsBusy() {
        let result = GroupBusyDay.on(
            day,
            availability: [blocked("them", on: day)],
            members: ["me", "them"],
            viewerID: "me",
            names: names
        )

        XCTAssertEqual(result.busyNames, ["Sam"])
        XCTAssertEqual(result.warning, "Sam isn't free then")
    }

    func testYourOwnBlockedDayIsNotNewsToYou() {
        let result = GroupBusyDay.on(
            day,
            availability: [blocked("me", on: day)],
            members: ["me", "them"],
            viewerID: "me",
            names: names
        )

        XCTAssertFalse(result.somebodyIsBusy)
        XCTAssertNil(result.warning)
    }

    /// The rule the type exists for: no document means nothing is known, not that they are free.
    func testSomebodyWhoHasNeverSharedIsCountedAsSilentRatherThanFree() {
        let result = GroupBusyDay.on(
            day,
            availability: [],
            members: ["me", "them", "third"],
            viewerID: "me",
            names: names
        )

        XCTAssertEqual(result.silentCount, 2)
        XCTAssertFalse(result.somebodyIsBusy)
        XCTAssertNil(result.warning, "silence alone is not worth a line under every date")
    }

    func testSharingAnEmptyCalendarIsNotSilence() {
        let result = GroupBusyDay.on(
            day,
            availability: [free("them")],
            members: ["me", "them"],
            viewerID: "me",
            names: names
        )

        XCTAssertEqual(result.silentCount, 0, "they have said, and what they said is that they are free")
        XCTAssertFalse(result.somebodyIsBusy)
    }

    func testTwoPeopleBusyReadAsAPlural() {
        let result = GroupBusyDay.on(
            day,
            availability: [blocked("them", on: day), blocked("third", on: day)],
            members: ["me", "them", "third"],
            viewerID: "me",
            names: names
        )

        XCTAssertEqual(result.busyNames, ["Priya", "Sam"])
        XCTAssertEqual(result.warning, "Priya and Sam aren't free then")
    }

    func testABusyPersonAndASilentOneAreBothReported() {
        let result = GroupBusyDay.on(
            day,
            availability: [blocked("them", on: day)],
            members: ["me", "them", "third", "fourth"],
            viewerID: "me",
            names: names
        )

        XCTAssertEqual(result.warning, "Sam isn't free then. 2 more haven't said.")
    }

    /// A warning that cannot name anybody is not actionable, so an unresolved name is skipped
    /// rather than rendered as "Someone".
    func testAnUnresolvedNameIsSkippedRatherThanGuessed() {
        let result = GroupBusyDay.on(
            day,
            availability: [blocked("stranger", on: day)],
            members: ["me", "stranger"],
            viewerID: "me",
            names: [:]
        )

        XCTAssertTrue(result.busyNames.isEmpty)
        XCTAssertNil(result.warning)
    }

    func testADayNobodyBlockedSaysNothing() {
        let other = Calendar.current.date(byAdding: .day, value: 3, to: day) ?? day
        let result = GroupBusyDay.on(
            day,
            availability: [blocked("them", on: other)],
            members: ["me", "them"],
            viewerID: "me",
            names: names
        )

        XCTAssertNil(result.warning)
    }
}
