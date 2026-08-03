import XCTest
import Factory
@testable import MiddleGround

/// Saying something must cost nothing.
///
/// Before `.comment` existed the composer's only send path was `.counter`, so a logistics question
/// on a plan three people had agreed to withdrew the agreement: status back to `countered`, every
/// acceptance voided, and three people who had said yes owing a fresh answer. These tests exist so
/// that cannot come back.
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

    /// The exact scenario that motivated this.
    func testAQuestionDoesNotUnpickAnAgreement() throws {
        var request = groupPlan()
        try request.addResponse(.init(senderID: "bob", responseType: .accept))
        try request.addResponse(.init(senderID: "carol", responseType: .accept))

        XCTAssertEqual(request.status, .accepted)
        let attendeesBefore = request.attendeeIDs
        let awaitingBefore = request.awaitingResponseFrom

        try request.addResponse(
            .init(senderID: "dave", responseType: .comment, text: "which entrance?")
        )

        XCTAssertEqual(request.status, .accepted, "a question is not a counter-proposal")
        XCTAssertTrue(request.hasAcceptance)
        XCTAssertEqual(request.attendeeIDs, attendeesBefore, "nobody's yes was taken away")
        XCTAssertEqual(
            request.awaitingResponseFrom,
            awaitingBefore,
            "the turn did not move, so nobody suddenly owes another answer"
        )
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

    /// Commenting is not answering, so it must not clear what someone owes.
    func testCommentingDoesNotCountAsAnswering() throws {
        var request = groupPlan()
        XCTAssertTrue(request.awaitingResponseFrom.contains("bob"))

        try request.addResponse(.init(senderID: "bob", responseType: .comment, text: "maybe!"))

        XCTAssertTrue(
            request.awaitingResponseFrom.contains("bob"),
            "bob still owes a yes or no"
        )
        XCTAssertTrue(request.canRespond(as: "bob"))
    }

    /// The whole point: you may speak when it is not your turn.
    func testAnyoneOnThePlanMaySpeakWheneverTheyLike() throws {
        var request = groupPlan()
        try request.addResponse(.init(senderID: "bob", responseType: .accept))

        XCTAssertFalse(request.canRespond(as: "bob"), "bob has answered")
        XCTAssertTrue(request.canComment(as: "bob"), "but he can still say something")
        XCTAssertNoThrow(
            try request.addResponse(
                .init(senderID: "bob", responseType: .comment, text: "shall I book?")
            )
        )
    }

    func testSomeoneNotOnThePlanCannotSpeak() {
        var request = groupPlan()
        XCTAssertFalse(request.canComment(as: "stranger"))
        XCTAssertThrowsError(
            try request.addResponse(
                .init(senderID: "stranger", responseType: .comment, text: "hi")
            )
        )
    }

    /// A cancelled plan is over. A thread that outlives its subject is a different product.
    func testACalledOffPlanCannotBeCommentedOn() throws {
        var request = groupPlan()
        request.status = .cancelled
        XCTAssertFalse(request.canComment(as: "bob"))

        var declined = groupPlan()
        declined.status = .declined
        XCTAssertFalse(declined.canComment(as: "bob"))
    }

    /// Comments should still be possible once a plan is done — "that was fun" is not a proposal.
    func testAFinishedPlanCanStillBeTalkedAbout() {
        var request = groupPlan()
        request.status = .completed
        XCTAssertTrue(request.canComment(as: "bob"))
    }

    /// Two people answering from the same stale copy must not lose one of the messages.
    ///
    /// This is what `appendMessage` buys. Writing the whole document from the caller's copy —
    /// which is what `updateRequest` does — meant the second write rebuilt the chain from a
    /// snapshot taken before the first, and the first message simply vanished. Turn-taking hid
    /// it while plans had two people; a group can have several people legitimately owing an
    /// answer at once, and comments let anyone speak at any time.
    func testTwoAnswersFromTheSameStaleCopyBothSurvive() async throws {
        AppConfiguration.useMockRepositories = true
        defer { AppConfiguration.useMockRepositories = false }

        let repository = MockRequestRepository()
        let service = RequestService(repository: repository)
        let plan = groupPlan()
        try await repository.createRequest(plan)

        // Both "clients" hold the copy from before either of them answered.
        let stale = plan
        _ = try await service.respond(to: stale, with: .accept, by: "bob")
        _ = try await service.respond(to: stale, with: .accept, by: "carol")

        let stored = try await repository.fetchRequests(for: "alice")
            .first { $0.id == plan.id }
        XCTAssertEqual(
            stored?.negotiationChain.count,
            2,
            "carol's answer was built from a copy that predates bob's, and must not erase it"
        )
        XCTAssertEqual(
            Set(stored?.negotiationChain.map(\.senderID) ?? []),
            ["bob", "carol"]
        )
    }

    /// The same hazard, from the direction comments opened up.
    func testACommentDoesNotEraseAnAnswerSentAtTheSameMoment() async throws {
        AppConfiguration.useMockRepositories = true
        defer { AppConfiguration.useMockRepositories = false }

        let repository = MockRequestRepository()
        let service = RequestService(repository: repository)
        let plan = groupPlan()
        try await repository.createRequest(plan)

        let stale = plan
        _ = try await service.respond(to: stale, with: .accept, by: "bob")
        _ = try await service.respond(to: stale, with: .comment, text: "running late", by: "carol")

        let stored = try await repository.fetchRequests(for: "alice")
            .first { $0.id == plan.id }
        XCTAssertEqual(stored?.negotiationChain.count, 2)
        XCTAssertEqual(stored?.status, .accepted, "the comment did not undo bob's yes")
    }
}
