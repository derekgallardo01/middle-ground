import XCTest
@testable import MiddleGround

/// Whether a group is still a group — and, more importantly, the cases where the honest answer is
/// "there is nothing to say yet".
///
/// The measure is built from plans that happened, never from activity. A test here exists for that
/// specifically: a group that talks constantly and never meets must not outrank one that meets
/// every fortnight and says little, because the second group is the one the product is for.
final class GroupEnergyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func days(_ count: Double) -> TimeInterval { count * 86_400 }

    private let group = Relationship(
        id: "rel_1",
        participantIDs: ["user_1", "user_2", "user_3"],
        type: .friends,
        name: "Sunday hikers"
    )

    /// A plan that everybody agreed happened, `daysAgo` back.
    private func happened(daysAgo: Double, id: String = UUID().uuidString) -> Request {
        var request = Request(
            id: id,
            creatorID: "user_1",
            recipientIDs: ["user_2"],
            category: .friends,
            title: "Dinner",
            proposedTime: now.addingTimeInterval(-days(daysAgo)),
            status: .completed,
            confirmations: ["user_1": .happened, "user_2": .happened]
        )
        request.status = .completed
        return request
    }

    private func upcoming(inDays: Double, id: String = UUID().uuidString) -> Request {
        var request = Request(
            id: id,
            creatorID: "user_1",
            recipientIDs: ["user_2"],
            category: .friends,
            title: "Drinks",
            proposedTime: now.addingTimeInterval(days(inDays)),
            status: .accepted
        )
        request.status = .accepted
        return request
    }

    /// Agreed, then called off — a plan that fell through.
    private func fellThrough(id: String = UUID().uuidString) -> Request {
        var request = Request(
            id: id,
            creatorID: "user_1",
            recipientIDs: ["user_2"],
            category: .friends,
            title: "Cinema",
            proposedTime: now.addingTimeInterval(-days(10)),
            status: .cancelled,
            negotiationChain: [
                NegotiationMessage(
                    senderID: "user_2",
                    responseType: .accept,
                    text: nil,
                    timestamp: now.addingTimeInterval(-days(20))
                )
            ]
        )
        request.status = .cancelled
        return request
    }

    // MARK: - Absence of evidence is not a low score

    func testANewGroupIsNotScoredForHavingJustFormed() {
        let energy = GroupEnergy.from(relationship: group, requests: [], now: now)

        XCTAssertEqual(energy.level, .notEnoughYet)
        XCTAssertNil(energy.ringProgress, "there is nothing honest to draw")
        XCTAssertFalse(energy.reason.isEmpty)
    }

    func testAGroupWithSomethingBookedButNoHistoryIsNotCooling() {
        let energy = GroupEnergy.from(relationship: group, requests: [upcoming(inDays: 5)], now: now)

        XCTAssertGreaterThanOrEqual(energy.level, .steady)
        XCTAssertEqual(energy.upcomingCount, 1)
    }

    // MARK: - Built from what happened, not from noise

    func testSeeingEachOtherRecentlyReadsAsWarm() {
        let energy = GroupEnergy.from(relationship: group, requests: [happened(daysAgo: 6)], now: now)

        XCTAssertEqual(energy.level, .warm)
        XCTAssertEqual(energy.daysSinceTogether, 6)
    }

    func testALongGapWithNothingPlannedIsCooling() {
        let energy = GroupEnergy.from(relationship: group, requests: [happened(daysAgo: 120)], now: now)

        XCTAssertEqual(energy.level, .cooling)
        XCTAssertTrue(energy.reason.contains("months ago"), energy.reason)
    }

    /// The point of the whole measure: a plan in the diary means the group is not cooling,
    /// whatever the gap behind it says.
    func testSomethingInTheDiaryLiftsALongGap() {
        let requests = [happened(daysAgo: 120), upcoming(inDays: 9)]

        let energy = GroupEnergy.from(relationship: group, requests: requests, now: now)

        XCTAssertEqual(energy.level, .steady)
        XCTAssertTrue(energy.reason.contains("One plan coming up."), energy.reason)
    }

    // MARK: - Plans that evaporate cost something

    func testAGroupWhosePlansFallThroughIsMarkedDown() {
        // Five settled plans, only one of which happened: below half, so it counts.
        var requests = [happened(daysAgo: 6, id: "r_ok")]
        requests += (0..<4).map { fellThrough(id: "r_bad_\($0)") }

        let energy = GroupEnergy.from(relationship: group, requests: requests, now: now)

        XCTAssertEqual(energy.level, .steady, "warm, minus one for a group that keeps calling off")
        XCTAssertTrue(energy.reason.contains("Under half"), energy.reason)
    }

    /// A percentage over two data points is a rumour — the same rule `GroupFollowThrough` keeps.
    func testTooFewPlansToJudgeFollowThroughDoesNotMarkDown() {
        let requests = [happened(daysAgo: 6, id: "r_ok"), fellThrough(id: "r_bad")]

        let energy = GroupEnergy.from(relationship: group, requests: requests, now: now)

        XCTAssertEqual(energy.level, .warm, "two plans is not evidence of a pattern")
        XCTAssertFalse(energy.reason.contains("Under half"))
    }

    // MARK: - Whose plans count

    func testAPlanBetweenPeopleFromAnotherGroupIsNotOurs() {
        var elsewhere = happened(daysAgo: 3)
        elsewhere.creatorID = "user_9"
        elsewhere.recipientIDs = ["user_8"]

        let energy = GroupEnergy.from(relationship: group, requests: [elsewhere], now: now)

        XCTAssertEqual(energy.level, .notEnoughYet)
    }

    /// Three of four going out is the ordinary case, and it is still the group getting together.
    func testAPlanWithSomeOfTheGroupCounts() {
        var partial = happened(daysAgo: 4)
        partial.creatorID = "user_2"
        partial.recipientIDs = ["user_3"]
        // Keyed to whoever is actually on it — a confirmation from somebody who is not counts for
        // nothing, and `isConfirmedComplete` waits for everybody.
        partial.confirmations = ["user_2": .happened, "user_3": .happened]

        let energy = GroupEnergy.from(relationship: group, requests: [partial], now: now)

        XCTAssertEqual(energy.level, .warm)
    }

    // MARK: - It always says why

    func testEveryLevelExplainsItself() {
        let cases: [[Request]] = [
            [],
            [upcoming(inDays: 5)],
            [happened(daysAgo: 6)],
            [happened(daysAgo: 120)],
            [happened(daysAgo: 45), upcoming(inDays: 3)]
        ]

        for requests in cases {
            let energy = GroupEnergy.from(relationship: group, requests: requests, now: now)
            XCTAssertFalse(
                energy.reason.isEmpty,
                "a ring with no sentence says you are failing without saying at what"
            )
        }
    }
}
