import XCTest
@testable import MiddleGround

final class RequestTests: XCTestCase {
    private let creator = "user_1"
    private let recipient = "user_2"
    private let outsider = "user_3"

    private func makeRequest(
        status: RequestStatus = .pending,
        category: RequestCategory = .relationship,
        title: String = "Date night?"
    ) -> Request {
        Request(
            creatorID: creator,
            recipientIDs: [recipient],
            category: category,
            title: title,
            status: status
        )
    }

    // MARK: - Status transitions

    func testRequestResponseUpdatesStatus() throws {
        var request = makeRequest()
        XCTAssertEqual(request.status, .pending)

        try request.addResponse(NegotiationMessage(senderID: recipient, responseType: .accept))

        XCTAssertEqual(request.status, .accepted)
        XCTAssertEqual(request.negotiationChain.count, 1)
    }

    func testCounterResponseMapsToCounteredStatus() throws {
        var request = makeRequest(category: .friends, title: "Dinner tonight?")

        try request.addResponse(
            NegotiationMessage(senderID: recipient, responseType: .counter, text: "How about 8pm?")
        )

        XCTAssertEqual(request.status, .countered)
        XCTAssertEqual(request.negotiationChain.first?.text, "How about 8pm?")
    }

    func testEveryResponseTypeMapsToAStatus() throws {
        for response in ResponseType.allCases {
            var request = makeRequest()
            try request.addResponse(NegotiationMessage(senderID: recipient, responseType: response))
            XCTAssertEqual(
                request.status,
                response.statusMapping,
                "\(response.rawValue) did not map to its status"
            )
        }
    }

    // MARK: - Roles
    //
    // A shared decision is only shared if the other person answers. These guard the rule that
    // a creator cannot respond to their own request — previously nothing checked, so a creator
    // could accept their own request, close it, and collect the XP.

    func testRecipientMayRespond() {
        XCTAssertTrue(makeRequest().canRespond(as: recipient))
    }

    func testCreatorMayNotRespondToTheirOwnRequest() {
        let request = makeRequest()
        XCTAssertFalse(request.canRespond(as: creator))
        XCTAssertTrue(request.isAwaitingResponse(for: creator))
    }

    func testNonParticipantMayNotRespond() {
        XCTAssertFalse(makeRequest().canRespond(as: outsider))
    }

    func testAddResponseRejectsTheCreator() {
        var request = makeRequest()
        XCTAssertThrowsError(
            try request.addResponse(NegotiationMessage(senderID: creator, responseType: .accept))
        ) { error in
            XCTAssertEqual(error as? RequestError, .notAllowedToRespond)
        }
        // A rejected response must leave the request untouched.
        XCTAssertEqual(request.status, .pending)
        XCTAssertTrue(request.negotiationChain.isEmpty)
    }

    func testAddResponseRejectsANonParticipant() {
        var request = makeRequest()
        XCTAssertThrowsError(
            try request.addResponse(NegotiationMessage(senderID: outsider, responseType: .decline))
        )
        XCTAssertEqual(request.status, .pending)
    }

    func testNobodyMayRespondOnceAnswered() {
        // `.save` used to be ungated, which let an accepted request be flipped to `.saved`,
        // destroying the accepted state with no way back.
        let request = makeRequest(status: .accepted)
        XCTAssertFalse(request.canRespond(as: recipient))
        XCTAssertFalse(request.canRespond(as: creator))
    }

    func testAddResponseRejectsAnAlreadyAnsweredRequest() {
        var request = makeRequest(status: .accepted)
        XCTAssertThrowsError(
            try request.addResponse(NegotiationMessage(senderID: recipient, responseType: .save))
        )
        XCTAssertEqual(request.status, .accepted, "an answered request must keep its status")
    }

    // MARK: - Turn taking
    //
    // The conversation used to end on the first reply: every response type mapped away from
    // `.pending`, and `canRespond` required `.pending`, so a counter froze the request forever
    // and the creator could never answer it. These pin the corrected behaviour.

    func testCreatorMayAnswerAfterTheRecipientCounters() throws {
        var request = makeRequest()
        try request.addResponse(
            NegotiationMessage(senderID: recipient, responseType: .counter, text: "8pm instead?")
        )

        XCTAssertEqual(request.status, .countered)
        XCTAssertTrue(request.isOpen, "a counter is a move in the conversation, not the end of it")
        XCTAssertTrue(request.canRespond(as: creator), "the turn must come back to the creator")
        XCTAssertFalse(request.canRespond(as: recipient), "you cannot answer your own message")
    }

    func testTheConversationCanRunSeveralTurns() throws {
        var request = makeRequest()
        try request.addResponse(NegotiationMessage(senderID: recipient, responseType: .counter, text: "8pm?"))
        try request.addResponse(NegotiationMessage(senderID: creator, responseType: .counter, text: "8:30?"))
        try request.addResponse(NegotiationMessage(senderID: recipient, responseType: .accept))

        XCTAssertEqual(request.negotiationChain.count, 3)
        XCTAssertEqual(request.status, .accepted)
        XCTAssertFalse(request.isOpen)
        XCTAssertFalse(request.canRespond(as: creator))
        XCTAssertFalse(request.canRespond(as: recipient))
    }

    func testAcceptAndDeclineStayTerminal() throws {
        for terminal in [ResponseType.accept, .decline] {
            var request = makeRequest()
            try request.addResponse(NegotiationMessage(senderID: recipient, responseType: terminal))
            XCTAssertFalse(request.isOpen, "\(terminal) must settle the decision")
            XCTAssertFalse(request.canRespond(as: creator))
            XCTAssertFalse(request.canRespond(as: recipient))
        }
    }

    func testAnOutsiderNeverGetsATurn() throws {
        var request = makeRequest()
        try request.addResponse(NegotiationMessage(senderID: recipient, responseType: .counter))
        XCTAssertFalse(request.canRespond(as: outsider))
        XCTAssertThrowsError(
            try request.addResponse(NegotiationMessage(senderID: outsider, responseType: .accept))
        )
    }

    /// Saving is a bookmark, not an answer — it must not hand the turn to the other person,
    /// and it must not lock the saver out of accepting later. Previously `.save` set a status
    /// that made `canRespond` false, so a saved request could never be accepted by anyone.
    func testSavingKeepsTheTurnAndLeavesTheRequestAnswerable() throws {
        var request = makeRequest()
        try request.addResponse(NegotiationMessage(senderID: recipient, responseType: .save))

        XCTAssertEqual(request.status, .saved)
        XCTAssertTrue(request.isOpen)
        XCTAssertTrue(request.canRespond(as: recipient), "the saver can still come back and accept")
        XCTAssertFalse(request.canRespond(as: creator), "saving does not demand anything of the creator")

        try request.addResponse(NegotiationMessage(senderID: recipient, responseType: .accept))
        XCTAssertEqual(request.status, .accepted)
    }

    func testAwaitingResponseFlipsWithTheTurn() throws {
        var request = makeRequest()
        XCTAssertTrue(request.isAwaitingResponse(for: creator))
        XCTAssertFalse(request.isAwaitingResponse(for: recipient))

        try request.addResponse(NegotiationMessage(senderID: recipient, responseType: .negotiate))
        XCTAssertFalse(request.isAwaitingResponse(for: creator), "it is now the creator's move")
        XCTAssertTrue(request.isAwaitingResponse(for: recipient))
    }

    func testAwaitingResponseIsFalseForOutsiders() {
        XCTAssertFalse(makeRequest().isAwaitingResponse(for: outsider))
    }

    // MARK: - Cancel

    func testTheCreatorMayWithdrawMidConversation() throws {
        var request = makeRequest()
        try request.addResponse(NegotiationMessage(senderID: recipient, responseType: .counter))
        XCTAssertTrue(request.canCancel(as: creator), "an unsettled request can still be withdrawn")
        XCTAssertFalse(request.canCancel(as: recipient))
    }

    func testOnlyTheCreatorMayCancel() {
        let request = makeRequest()
        XCTAssertTrue(request.canCancel(as: creator))
        XCTAssertFalse(request.canCancel(as: recipient))
        XCTAssertFalse(request.canCancel(as: outsider))
    }

    func testAnAnsweredRequestCannotBeCancelled() {
        XCTAssertFalse(makeRequest(status: .accepted).canCancel(as: creator))
    }

    // MARK: - Participants

    func testAllParticipantIDsIncludesBothSides() {
        let request = makeRequest()
        XCTAssertTrue(request.allParticipantIDs.contains(creator))
        XCTAssertTrue(request.allParticipantIDs.contains(recipient))
        XCTAssertEqual(request.allParticipantIDs.count, 2)
    }

    // MARK: - Presentation

    func testRequestStatusDisplayName() {
        XCTAssertEqual(RequestStatus.pending.displayName, "Pending")
        XCTAssertEqual(RequestStatus.accepted.displayName, "Accepted")
        XCTAssertEqual(RequestStatus.declined.displayName, "Declined")
    }

    func testRequestStatusColor() {
        XCTAssertEqual(RequestStatus.accepted.color, MGColors.teal)
        XCTAssertEqual(RequestStatus.declined.color, MGColors.coral)
    }

    // MARK: - Cancellation
    //
    // Cancelling used to delete the document, which erased the fact a plan had ever been made —
    // and with it any chance of "cancelled three times in a row" meaning something.

    func testACancelledRequestIsClosedAndAnswerableByNobody() {
        var request = Request.preview
        request.status = .cancelled

        XCTAssertFalse(request.isOpen)
        XCTAssertTrue(request.awaitingResponseFrom.isEmpty)
        XCTAssertFalse(request.canCancel(as: request.creatorID), "it cannot be cancelled twice")
    }

    func testCancellingIsOnlyForTheCreatorAndOnlyWhileOpen() {
        let request = Request.previewAwaitingMe

        XCTAssertTrue(request.canCancel(as: request.creatorID))
        XCTAssertFalse(request.canCancel(as: request.recipientIDs[0]))

        var settled = request
        settled.status = .accepted
        XCTAssertFalse(settled.canCancel(as: settled.creatorID))
    }

    func testEveryCancellationReasonHasAName() {
        for reason in CancellationReason.allCases {
            XCTAssertFalse(reason.displayName.isEmpty, "\(reason) has no display name")
        }
    }

    // MARK: - Reliability
    //
    // Every assertion here is a place the score could quietly become unfair.

    private func plan(
        _ status: RequestStatus,
        creator: String = "me",
        confirmations: [String: ConfirmationOutcome] = [:],
        proposedTime: Date? = nil,
        updatedAt: Date = Date()
    ) -> Request {
        Request(
            creatorID: creator,
            recipientIDs: creator == "me" ? ["them"] : ["me"],
            category: .daily,
            title: "Plan",
            proposedTime: proposedTime,
            status: status,
            confirmations: confirmations,
            updatedAt: updatedAt
        )
    }

    /// One missed plan is not a pattern, and "0%" beside a single data point is a libel.
    func testNoScoreUntilThereIsEnoughToSay() {
        let requests = [
            plan(.completed, confirmations: ["me": .happened, "them": .happened])
        ]
        let score = ReliabilityScore.from(requests: requests, userID: "me")

        XCTAssertNil(score.percentage)
        XCTAssertFalse(score.hasEnoughData)
    }

    func testAttendedPlansRaiseTheScore() {
        let attended = (0..<5).map { _ in
            plan(.completed, confirmations: ["me": .happened, "them": .happened])
        }
        let score = ReliabilityScore.from(requests: attended, userID: "me")

        XCTAssertEqual(score.attended, 5)
        XCTAssertEqual(score.percentage, 100)
    }

    /// If the two people disagree, the app does not get to pick a winner.
    func testADisputedPlanScoresNothingEitherWay() {
        let disputed = (0..<5).map { _ in
            plan(.accepted, confirmations: ["me": .happened, "them": .didNotHappen])
        }
        let score = ReliabilityScore.from(requests: disputed, userID: "me")

        XCTAssertEqual(score.settledCount, 0, "a contested plan counts for nobody")
        XCTAssertNil(score.percentage)
    }

    /// An unanswered confirmation is not a no-show, or the score punishes people for not
    /// opening an app.
    func testSilenceIsNotAMissedPlan() {
        let unanswered = (0..<5).map { _ in plan(.accepted, confirmations: ["me": .happened]) }
        let score = ReliabilityScore.from(requests: unanswered, userID: "me")

        XCTAssertEqual(score.missed, 0)
        XCTAssertEqual(score.settledCount, 0)
    }

    /// Cancelling a week out is courtesy; an hour before is the thing people mind.
    func testOnlyLateCancellationsCount() {
        let now = Date()
        let early = plan(
            .cancelled,
            proposedTime: now.addingTimeInterval(7 * 24 * 3600),
            updatedAt: now
        )
        let late = plan(
            .cancelled,
            proposedTime: now.addingTimeInterval(3600),
            updatedAt: now
        )

        XCTAssertFalse(early.wasCancelledLate)
        XCTAssertTrue(late.wasCancelledLate)
    }

    func testCancellationStreakBreaksOnAPlanThatWentAhead() {
        let now = Date()
        let requests = [
            plan(.cancelled, updatedAt: now),
            plan(.cancelled, updatedAt: now.addingTimeInterval(-100)),
            plan(.completed,
                 confirmations: ["me": .happened, "them": .happened],
                 updatedAt: now.addingTimeInterval(-200)),
            plan(.cancelled, updatedAt: now.addingTimeInterval(-300))
        ]
        let score = ReliabilityScore.from(requests: requests, userID: "me")

        XCTAssertEqual(score.cancellationStreak, 2, "the run stops at the plan they kept")
        XCTAssertFalse(score.isCancellingRepeatedly)
    }

    /// Somebody else's cancellation says nothing about you.
    func testAnotherPersonsCancellationDoesNotCountAgainstYou() {
        let requests = [plan(.cancelled, creator: "them", proposedTime: Date(), updatedAt: Date())]
        let score = ReliabilityScore.from(requests: requests, userID: "me")

        XCTAssertEqual(score.lateCancellations, 0)
        XCTAssertEqual(score.cancellationStreak, 0)
    }

    // MARK: - Stakes
    //
    // The settlement is derived rather than stored, which is what makes it safe: a stored one
    // would have to be writable by whoever confirms attendance, and anyone who can write it can
    // claim it.

    private func staked(
        _ confirmations: [String: ConfirmationOutcome],
        status: RequestStatus = .accepted,
        accepted: Bool = true
    ) -> Request {
        var request = Request(
            creatorID: "me",
            recipientIDs: ["them"],
            category: .daily,
            title: "Plan",
            proposedTime: Date().addingTimeInterval(-3600),
            status: status,
            confirmations: confirmations
        )
        request.stake = Stake(proposedBy: "me", points: 25, acceptedBy: accepted ? "them" : nil)
        return request
    }

    func testAStakeIsOnlyLiveOnceTheOtherPersonAgrees() {
        let stake = Stake(proposedBy: "me", points: 25)

        XCTAssertFalse(stake.isAccepted)
        XCTAssertFalse(stake.canAccept("me"), "you cannot agree with yourself")
        XCTAssertTrue(stake.canAccept("them"))
    }

    func testAnUnacceptedStakeNeverSettles() {
        let request = staked(["me": .happened, "them": .happened], accepted: false)
        XCTAssertNil(request.stakeSettlement)
        XCTAssertEqual(request.stakeOutcome(for: "me"), 0)
    }

    func testBothTurningUpReturnsTheStakeAsABonus() {
        let request = staked(["me": .happened, "them": .happened], status: .completed)

        XCTAssertEqual(request.stakeSettlement, .kept)
        XCTAssertEqual(request.stakeOutcome(for: "me"), 25)
        XCTAssertEqual(request.stakeOutcome(for: "them"), 25)
    }

    /// Both lose, never one at the other's expense: the record says whether it happened, not
    /// whose fault it was.
    func testAPlanThatDidNotHappenCostsBothSides() {
        let request = staked(["me": .didNotHappen, "them": .didNotHappen])

        XCTAssertEqual(request.stakeSettlement, .forfeited)
        XCTAssertEqual(request.stakeOutcome(for: "me"), -25)
        XCTAssertEqual(request.stakeOutcome(for: "them"), -25)
    }

    func testADisputedPlanSettlesNoStake() {
        let request = staked(["me": .happened, "them": .didNotHappen])
        XCTAssertNil(request.stakeSettlement)
    }

    /// One person cannot collect by answering alone.
    func testOneAnswerSettlesNothing() {
        let request = staked(["me": .happened])
        XCTAssertNil(request.stakeSettlement)
        XCTAssertEqual(request.stakeOutcome(for: "me"), 0)
    }

    func testSomeoneOutsideThePlanGetsNothing() {
        let request = staked(["me": .happened, "them": .happened], status: .completed)
        XCTAssertEqual(request.stakeOutcome(for: "stranger"), 0)
    }

    // MARK: - Unknown categories
    //
    // A category added in a later release used to make every request using it silently vanish for
    // anyone on an older build: decoding returned nil and the repository compactMapped it away, so
    // there was no error to notice — the request simply was not in the list. These pin the
    // fallback, because the failure it prevents is invisible by construction.

    func testAnUnrecognisedCategoryDecodesToUnknownRatherThanFailing() {
        XCTAssertEqual(RequestCategory(storedValue: "poker_night"), .unknown)
        XCTAssertEqual(RequestCategory(storedValue: ""), .unknown)
    }

    func testKnownCategoriesStillDecodeToThemselves() {
        for category in RequestCategory.allCases {
            XCTAssertEqual(RequestCategory(storedValue: category.rawValue), category)
        }
    }

    /// `.unknown` is a decoding destination, never a choice. It must not appear in the compose
    /// picker, which is driven by `allCases`.
    func testUnknownIsNotSelectable() {
        XCTAssertFalse(RequestCategory.allCases.contains(.unknown))
        XCTAssertTrue(RequestCategory.allCases.contains(.dating))
        XCTAssertTrue(RequestCategory.allCases.contains(.chill))
    }

    func testEveryCategoryHasADisplayNameAndIcon() {
        for category in RequestCategory.allCases + [.unknown] {
            XCTAssertFalse(category.displayName.isEmpty, "\(category) has no display name")
            XCTAssertFalse(category.iconName.isEmpty, "\(category) has no icon")
        }
    }
}
