import XCTest
@testable import MiddleGround

/// The exclusions matter more than the ranking. A leaderboard that ranks two partners is the one
/// outcome this feature must never produce, and it is the easiest one to reach by accident.
final class GroupScoreboardTests: XCTestCase {
    private let alice = "alice"
    private let bob = "bob"
    private let carol = "carol"

    private var names: [String: String] {
        [alice: "Alice", bob: "Bob", carol: "Carol"]
    }

    private func group(
        _ type: RelationshipType = .friends,
        members: [String]
    ) -> Relationship {
        Relationship(id: "g1", participantIDs: members, type: type, inviteCode: "ABC123")
    }

    /// A settled plan among the given people, either attended or not.
    private func plan(
        creator: String,
        others: [String],
        happened: Bool,
        id: String = UUID().uuidString
    ) -> Request {
        let everyone = [creator] + others
        return Request(
            id: id,
            creatorID: creator,
            recipientIDs: others,
            category: .friends,
            title: "Dinner",
            proposedTime: Date().addingTimeInterval(-72 * 3600),
            status: happened ? .completed : .accepted,
            confirmations: Dictionary(
                uniqueKeysWithValues: everyone.map { ($0, happened ? .happened : .didNotHappen) }
            )
        )
    }

    private func attendedPlans(_ count: Int, among people: [String]) -> [Request] {
        (0..<count).map {
            plan(creator: people[0], others: Array(people.dropFirst()), happened: true, id: "a\($0)")
        }
    }

    // MARK: - The exclusions

    func testACoupleNeverGetsAScoreboard() {
        let couple = group(.couple, members: [alice, bob])
        XCTAssertFalse(GroupScoreboard.isEligible(couple))
        XCTAssertNil(
            GroupScoreboard.from(
                relationship: couple,
                requests: attendedPlans(10, among: [alice, bob]),
                names: names
            ),
            "no amount of history may produce a ranking between two partners"
        )
    }

    /// The check that the type test alone would miss.
    func testTwoPeopleNeverGetAScoreboardWhateverTheGroupIsCalled() {
        for type in RelationshipType.allCases {
            let pair = group(type, members: [alice, bob])
            XCTAssertFalse(
                GroupScoreboard.isEligible(pair),
                "a two-person \(type.rawValue) group is still two people being ranked"
            )
        }
    }

    func testThreeFriendsAreEligible() {
        XCTAssertTrue(GroupScoreboard.isEligible(group(members: [alice, bob, carol])))
    }

    // MARK: - What counts

    /// A plan with an outsider, reached through a plan invite, is not this group's business.
    func testPlansInvolvingSomeoneOutsideTheGroupDoNotCount() {
        let trio = group(members: [alice, bob, carol])
        let outsiderPlans = (0..<10).map {
            plan(creator: alice, others: ["stranger"], happened: true, id: "o\($0)")
        }

        let board = GroupScoreboard.from(
            relationship: trio, requests: outsiderPlans, names: names
        )
        XCTAssertEqual(board?.ranked.count, 0, "none of those plans were within the group")
    }

    func testAPlanBetweenTwoOfThreeMembersStillCounts() {
        let trio = group(members: [alice, bob, carol])
        let board = GroupScoreboard.from(
            relationship: trio,
            requests: attendedPlans(6, among: [alice, bob]),
            names: names
        )
        XCTAssertEqual(board?.ranked.map(\.userID).sorted(), [alice, bob].sorted())
    }

    // MARK: - Ranking

    /// Only a late cancellation is personal. A plan everyone agreed did not happen counts against
    /// everyone who said so — see `testAGroupNoShowCountsAgainstEveryoneOnIt` — so it is
    /// cancellations, not no-shows, that separate people on the board.
    func testCallingThingsOffLateRanksYouLower() throws {
        let trio = group(members: [alice, bob, carol])
        var requests = attendedPlans(6, among: [alice, bob, carol])
        requests += (0..<3).map { index in
            let at = Date().addingTimeInterval(-Double(index) * 3600)
            return Request(
                id: "lc\(index)",
                creatorID: bob,
                recipientIDs: [alice, carol],
                category: .friends,
                title: "Drinks",
                proposedTime: at,
                status: .cancelled,
                updatedAt: at
            )
        }

        let board = try XCTUnwrap(GroupScoreboard.from(
            relationship: trio,
            requests: requests,
            names: names
        ))
        XCTAssertEqual(board.ranked.first?.rank, 1)
        XCTAssertEqual(
            board.ranked.last?.userID,
            bob,
            "the person who called three off at the last minute sits last, not first"
        )
        XCTAssertEqual(board.ranked.count, 3)
    }

    /// Worth pinning because it is the opposite of what a scoreboard might lead you to expect:
    /// nobody turned up, so nobody gets credit for turning up. It also means a group no-show
    /// cannot be used to push one person down the board.
    func testAGroupNoShowCountsAgainstEveryoneOnIt() throws {
        let trio = group(members: [alice, bob, carol])
        var requests = attendedPlans(6, among: [alice, bob, carol])
        requests += (0..<3).map {
            plan(creator: bob, others: [alice, carol], happened: false, id: "m\($0)")
        }

        let board = try XCTUnwrap(GroupScoreboard.from(
            relationship: trio,
            requests: requests,
            names: names
        ))
        let percentages = Set(board.ranked.compactMap(\.percentage))
        XCTAssertEqual(
            percentages.count,
            1,
            "a plan nobody turned up to says nothing about who is more reliable"
        )
    }

    /// Being new is not a score.
    func testSomeoneWithoutEnoughHistoryIsListedButNotRanked() throws {
        let trio = group(members: [alice, bob, carol])
        // Only Alice and Bob have a full history; Carol has one plan.
        var requests = attendedPlans(6, among: [alice, bob])
        requests.append(plan(creator: carol, others: [alice], happened: true, id: "c1"))

        let board = try XCTUnwrap(GroupScoreboard.from(
            relationship: trio,
            requests: requests,
            names: names
        ))
        XCTAssertEqual(board.unranked.map(\.userID), [carol])
        XCTAssertNil(board.unranked.first?.percentage)
        XCTAssertEqual(board.entries.count, 3, "everyone is listed, ranked or not")
    }

    func testABoardWithOnlyOneRankedPersonIsNotWorthShowing() {
        let trio = group(members: [alice, bob, carol])
        let board = GroupScoreboard.from(
            relationship: trio,
            requests: attendedPlans(6, among: [alice, carol]).filter { _ in true },
            names: names
        )
        // Alice and Carol both qualify here, so the board is worth showing.
        XCTAssertEqual(board?.isWorthShowing, true)

        let sparse = GroupScoreboard.from(relationship: trio, requests: [], names: names)
        XCTAssertEqual(
            sparse?.isWorthShowing,
            false,
            "one number on its own is a profile, not a scoreboard"
        )
    }

    func testEveryoneIsListedEvenWithoutAName() {
        let trio = group(members: [alice, bob, carol])
        let board = GroupScoreboard.from(
            relationship: trio,
            requests: attendedPlans(6, among: [alice, bob, carol]),
            names: [alice: "Alice"]
        )
        XCTAssertEqual(board?.entries.count, 3, "a missing name must not change the ranking")
    }
}
