import XCTest
import Factory
@testable import MiddleGround

/// Saying something must cost nothing, and must not be stored where it can hurt.
///
/// The original failure: the composer's only send path was `.counter`, a *proposal*, so asking
/// "which entrance?" on a plan three people had agreed to withdrew the agreement — status back to
/// `countered`, every acceptance voided, three people owing a fresh answer. Conversation now lives
/// in `requests/{id}/messages` and cannot touch the decision at all, which is the strongest form
/// of that guarantee: not "a comment does not change the status" but "a comment is not on the
/// object the status is computed from".
final class CommentTests: XCTestCase {
    private func groupPlan() -> Request {
        Request(
            creatorID: "alice",
            recipientIDs: ["bob", "carol", "dave"],
            category: .friends,
            title: "Dinner Friday",
            proposedTime: Date().addingTimeInterval(72 * 3600),
            location: "Lucia's"
        )
    }

    // MARK: - Conversation cannot move a decision

    func testAMessageIsNotOnTheObjectTheStatusIsComputedFrom() throws {
        var request = groupPlan()
        try request.addResponse(.init(senderID: "bob", responseType: .accept))
        try request.addResponse(.init(senderID: "carol", responseType: .accept))

        let before = (request.status, request.attendeeIDs, request.awaitingResponseFrom)

        // A message is a separate document. There is no code path by which it reaches here.
        _ = PlanMessage(senderID: "dave", text: "which entrance?")

        XCTAssertEqual(request.status, before.0)
        XCTAssertEqual(request.attendeeIDs, before.1)
        XCTAssertEqual(request.awaitingResponseFrom, before.2)
        XCTAssertTrue(request.hasAcceptance)
    }

    /// The contrast: attaching a time *is* a proposal, and still behaves like one.
    func testAttachingATimeStillResetsTheRoom() throws {
        var request = groupPlan()
        try request.addResponse(.init(senderID: "bob", responseType: .accept))
        try request.addResponse(.init(senderID: "carol", responseType: .accept))

        try request.addResponse(
            .init(senderID: "dave", responseType: .counter, text: "Sunday instead?")
        )

        XCTAssertEqual(request.status, .countered)
        XCTAssertFalse(request.hasAcceptance, "an old yes is not a yes to the new time")
    }

    // MARK: - Who may speak

    func testAnyoneOnThePlanMaySpeakWheneverTheyLike() throws {
        var request = groupPlan()
        try request.addResponse(.init(senderID: "bob", responseType: .accept))

        XCTAssertFalse(request.canRespond(as: "bob"), "bob has answered")
        XCTAssertTrue(request.canMessage(as: "bob"), "but he can still say something")
    }

    func testSomeoneNotOnThePlanCannotSpeak() {
        XCTAssertFalse(groupPlan().canMessage(as: "stranger"))
    }

    /// A cancelled plan is over. A thread that outlives its subject is a different product.
    func testACalledOffPlanCannotBeMessaged() {
        for status in [RequestStatus.cancelled, .declined] {
            var request = groupPlan()
            request.status = status
            XCTAssertFalse(request.canMessage(as: "bob"), "\(status.rawValue) is over")
        }
    }

    func testAFinishedPlanCanStillBeTalkedAbout() {
        var request = groupPlan()
        request.status = .completed
        XCTAssertTrue(request.canMessage(as: "bob"))
    }

    // MARK: - Storage

    /// Independent documents, so simultaneous senders cannot overwrite each other. This is the
    /// property the negotiation chain had to buy with a transaction.
    func testTwoPeopleSendingAtOnceBothLand() async throws {
        let repository = MockPlanMessageRepository()
        try await repository.send(.init(senderID: "bob", text: "on my way"), forRequest: "r1")
        try await repository.send(.init(senderID: "carol", text: "me too"), forRequest: "r1")

        let stored = try await repository.messages(forRequest: "r1", limit: 100)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(Set(stored.map(\.senderID)), ["bob", "carol"])
    }

    func testMessagesComeBackOldestFirst() async throws {
        let repository = MockPlanMessageRepository()
        let now = Date()
        try await repository.send(
            .init(senderID: "bob", text: "second", at: now), forRequest: "r1"
        )
        try await repository.send(
            .init(senderID: "carol", text: "first", at: now.addingTimeInterval(-60)),
            forRequest: "r1"
        )

        let stored = try await repository.messages(forRequest: "r1", limit: 100)
        XCTAssertEqual(stored.map(\.text), ["first", "second"])
    }

    // MARK: - Threads

    func testRepliesAreCollapsedUnderTheirParentRatherThanShownInline() {
        let parent = PlanMessage(id: "p1", senderID: "alice", text: "which entrance?")
        let reply = PlanMessage(senderID: "bob", text: "the one on Fourth", parentID: "p1")
        let separate = PlanMessage(senderID: "carol", text: "running late")

        let transcript = TranscriptEntry.transcript(
            decisions: [],
            messages: [parent, reply, separate]
        )

        XCTAssertEqual(transcript.count, 2, "the reply belongs under its parent, not in the timeline")
        XCTAssertEqual(TranscriptEntry.replies(to: "p1", in: [parent, reply, separate]), [reply])
    }

    func testTheTranscriptInterleavesDecisionsAndMessagesByTime() {
        let start = Date()
        let decision = NegotiationMessage(
            senderID: "alice",
            responseType: .counter,
            text: "Sunday?",
            timestamp: start.addingTimeInterval(60)
        )
        let earlier = PlanMessage(senderID: "bob", text: "before", at: start)
        let later = PlanMessage(senderID: "carol", text: "after", at: start.addingTimeInterval(120))

        let transcript = TranscriptEntry.transcript(
            decisions: [decision],
            messages: [later, earlier]
        )
        XCTAssertEqual(transcript.map(\.text), ["before", "Sunday?", "after"])
    }
}
