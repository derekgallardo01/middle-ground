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

    // MARK: - Cancel

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
}
