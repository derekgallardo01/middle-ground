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
