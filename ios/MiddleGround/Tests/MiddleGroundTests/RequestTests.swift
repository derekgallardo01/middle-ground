import XCTest
@testable import MiddleGround

final class RequestTests: XCTestCase {
    func testRequestResponseUpdatesStatus() async {
        var request = Request(
            creatorID: "user_1",
            recipientIDs: ["user_2"],
            category: .relationship,
            title: "Date night?"
        )

        XCTAssertEqual(request.status, .pending)

        let message = NegotiationMessage(
            senderID: "user_2",
            responseType: .accept
        )
        request.addResponse(message)

        XCTAssertEqual(request.status, .accepted)
        XCTAssertEqual(request.negotiationChain.count, 1)
    }

    func testCounterResponseMapsToCounteredStatus() async {
        var request = Request(
            creatorID: "user_1",
            recipientIDs: ["user_2"],
            category: .friends,
            title: "Dinner tonight?"
        )

        let message = NegotiationMessage(
            senderID: "user_2",
            responseType: .counter,
            text: "How about 8pm?"
        )
        request.addResponse(message)

        XCTAssertEqual(request.status, .countered)
        XCTAssertEqual(request.negotiationChain.first?.text, "How about 8pm?")
    }

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
