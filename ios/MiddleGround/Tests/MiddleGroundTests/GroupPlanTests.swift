import XCTest
@testable import MiddleGround

/// Three people change what a plan means, and every one of these tests is a case that was either
/// wrong or undefined when a group could only ever hold two.
///
/// The two-person behaviour is asserted alongside the group behaviour throughout, because the
/// risk in this change is not that groups misbehave — it is that pairs quietly stop working.
final class GroupPlanTests: XCTestCase {
    private let alice = "alice"
    private let bob = "bob"
    private let cara = "cara"

    private func plan(recipients: [String], chain: [NegotiationMessage] = [], status: RequestStatus = .pending) -> Request {
        Request(
            creatorID: alice,
            recipientIDs: recipients,
            category: .friends,
            title: "Dinner",
            proposedTime: Date().addingTimeInterval(3600),
            status: status,
            negotiationChain: chain
        )
    }

    private func message(_ sender: String, _ type: ResponseType) -> NegotiationMessage {
        NegotiationMessage(senderID: sender, responseType: type)
    }

    // MARK: - Whose turn it is

    func testEveryoneOwesAnAnswerBeforeAnybodyReplies() {
        let request = plan(recipients: [bob, cara])
        XCTAssertEqual(Set(request.awaitingResponseFrom), [bob, cara])
    }

    /// The creator proposed it. Proposing is committing, so they owe nothing until somebody
    /// changes what is on the table.
    func testTheCreatorDoesNotOweAnAnswerToTheirOwnPlan() {
        XCTAssertFalse(plan(recipients: [bob, cara]).canRespond(as: alice))
    }

    /// The old rule was "everyone except whoever sent the last message". With three people that
    /// handed the turn back to the creator the moment one person replied, while the person who
    /// had not replied at all was counted as owing nothing.
    func testOneReplyDoesNotHandTheTurnToTheCreator() {
        let request = plan(
            recipients: [bob, cara],
            chain: [message(bob, .save)]
        )
        XCTAssertEqual(Set(request.awaitingResponseFrom), [bob, cara])
        XCTAssertFalse(request.canRespond(as: alice))
    }

    /// A counter puts a different plan on the table, so everyone else owes a fresh answer to it —
    /// including anyone who had already answered the previous version.
    func testACounterResetsWhoOwesAnAnswer() {
        let request = plan(
            recipients: [bob, cara],
            chain: [message(bob, .counter)],
            status: .countered
        )
        XCTAssertEqual(Set(request.awaitingResponseFrom), [alice, cara])
        XCTAssertFalse(request.canRespond(as: bob), "the person who countered does not answer themselves")
    }

    func testTwoPersonTurnTakingIsUnchanged() {
        XCTAssertEqual(plan(recipients: [bob]).awaitingResponseFrom, [bob])

        let countered = plan(recipients: [bob], chain: [message(bob, .counter)], status: .countered)
        XCTAssertEqual(countered.awaitingResponseFrom, [alice])
    }

    /// A save is a bookmark, not an answer. It must leave the turn exactly where it was, or a
    /// recipient who saved could never afterwards accept.
    func testSavingLeavesTheTurnWhereItWas() {
        let request = plan(recipients: [bob], chain: [message(bob, .save)], status: .saved)
        XCTAssertEqual(request.awaitingResponseFrom, [bob])
    }

    // MARK: - What a decline means

    /// The failure this prevents: one person declining a plan three others agreed to. That is not
    /// a decline, it is a cancellation, and only the creator may do that.
    func testOnePersonDecliningDoesNotCallOffAGroupPlan() throws {
        var request = plan(recipients: [bob, cara])
        try request.addResponse(message(bob, .decline))

        XCTAssertNotEqual(request.status, .declined)
        XCTAssertTrue(request.acceptsResponses)
        XCTAssertEqual(request.awaitingResponseFrom, [cara])
    }

    func testAGroupPlanIsDeclinedOnlyWhenNobodyIsLeft() throws {
        var request = plan(recipients: [bob, cara])
        try request.addResponse(message(bob, .decline))
        try request.addResponse(message(cara, .decline))

        XCTAssertEqual(request.status, .declined)
        XCTAssertFalse(request.acceptsResponses)
    }

    func testATwoPersonDeclineStillSettlesImmediately() throws {
        var request = plan(recipients: [bob])
        try request.addResponse(message(bob, .decline))

        XCTAssertEqual(request.status, .declined)
        XCTAssertFalse(request.acceptsResponses)
    }

    /// Once somebody is coming, the plan is on. A later decline is "not me", not "not happening".
    func testADeclineAfterAnAcceptanceLeavesThePlanOn() throws {
        var request = plan(recipients: [bob, cara])
        try request.addResponse(message(bob, .accept))
        try request.addResponse(message(cara, .decline))

        XCTAssertEqual(request.status, .accepted)
    }

    // MARK: - Accepting does not lock the others out

    /// With two people an acceptance settles it. With three, one friend saying yes must not stop
    /// the others saying yes too. `firestore.rules` carries the same exception.
    func testAnAcceptedGroupPlanStillOwesAnswers() throws {
        var request = plan(recipients: [bob, cara])
        try request.addResponse(message(bob, .accept))

        XCTAssertEqual(request.status, .accepted)
        XCTAssertTrue(request.acceptsResponses)
        XCTAssertTrue(request.canRespond(as: cara))
    }

    func testAnAcceptedTwoPersonPlanIsClosed() throws {
        var request = plan(recipients: [bob])
        try request.addResponse(message(bob, .accept))

        XCTAssertFalse(request.acceptsResponses)
        XCTAssertTrue(request.awaitingResponseFrom.isEmpty)
    }

    func testACancelledPlanAcceptsNothing() {
        let request = plan(recipients: [bob, cara], status: .cancelled)
        XCTAssertFalse(request.acceptsResponses)
        XCTAssertTrue(request.awaitingResponseFrom.isEmpty)
    }

    // MARK: - Who is actually coming

    func testAttendeesAreTheProposerPlusWhoeverAccepted() throws {
        var request = plan(recipients: [bob, cara])
        try request.addResponse(message(bob, .accept))
        try request.addResponse(message(cara, .decline))

        XCTAssertEqual(Set(request.attendeeIDs), [alice, bob])
    }

    /// An acceptance of a time that has since been countered is not an acceptance of the new one.
    func testACounterClearsEarlierAcceptances() throws {
        var request = plan(recipients: [bob, cara])
        try request.addResponse(message(bob, .accept))
        try request.addResponse(message(cara, .counter))

        XCTAssertFalse(request.hasAcceptance)
        XCTAssertEqual(request.attendeeIDs, [cara], "the counter's sender is now the proposer")
    }

    // MARK: - Seats

    func testACoupleHoldsExactlyTwo() {
        XCTAssertEqual(RelationshipType.couple.seatLimit, 2)
        let couple = Relationship(id: "r", participantIDs: ["a"], type: .couple)
        XCTAssertEqual(couple.seatCount, 2)
    }

    func testOtherGroupsHoldMoreThanTwo() {
        for type in RelationshipType.allCases where type != .couple {
            XCTAssertGreaterThan(type.seatLimit, 2, "\(type.rawValue) should hold more than two")
        }
    }

    /// Absence means two. Every group written before seats existed could hold exactly two people,
    /// and reading a missing value as unlimited would silently widen all of them.
    func testAGroupWithNoStoredSeatCountHoldsTwo() throws {
        let json = """
        {"id":"r1","participantIDs":["a","b"],"type":"friends",
         "createdAt":0,"growthScore":0,"inviteCode":"MG24KT"}
        """
        let decoded = try JSONDecoder().decode(Relationship.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.seatCount, 2)
        XCTAssertFalse(decoded.hasRoom)
    }

    func testRoomIsWhatDecidesWhetherSomeoneCanJoin() {
        var group = Relationship(id: "r", participantIDs: ["a"], type: .friends)
        XCTAssertTrue(group.hasRoom)

        group.participantIDs = Array(repeating: "x", count: group.seatCount)
        XCTAssertFalse(group.hasRoom)
    }

    func testOtherIDsReturnsEverybodyElse() {
        let group = Relationship(id: "r", participantIDs: [alice, bob, cara], type: .friends)
        XCTAssertEqual(Set(group.otherIDs(excluding: alice)), [bob, cara])
    }
}
