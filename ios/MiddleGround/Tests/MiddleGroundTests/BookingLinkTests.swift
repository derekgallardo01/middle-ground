import XCTest
import Factory
@testable import MiddleGround

/// When the booking row appears, and what it records when followed.
///
/// The gating is the part most worth pinning: an offer to book a table on a plan nobody has
/// agreed to is worse than no offer at all, and a link that quietly fails to appear on a plan
/// that *is* agreed is invisible until somebody complains.
@MainActor
final class BookingLinkTests: XCTestCase {
    private var outcomes: MockPlanOutcomeRepository!

    override func setUp() {
        super.setUp()
        AppConfiguration.useMockRepositories = true
        let repository = MockPlanOutcomeRepository()
        outcomes = repository
        Container.shared.authService.register { MockAuthService() }
        Container.shared.planOutcomeRepository.register { repository }
    }

    override func tearDown() {
        Container.shared.authService.reset()
        Container.shared.planOutcomeRepository.reset()
        AppConfiguration.useMockRepositories = false
        outcomes = nil
        super.tearDown()
    }

    private func makeRequest(
        status: RequestStatus,
        location: String?,
        recipients: [String] = ["user_2"]
    ) -> Request {
        Request(
            creatorID: "user_1",
            recipientIDs: recipients,
            category: .friends,
            title: "Dinner?",
            proposedTime: Date().addingTimeInterval(48 * 3600),
            location: location,
            status: status
        )
    }

    func testAnAgreedPlanWithAPlaceOffersALink() async {
        let viewModel = RequestDetailViewModel(
            request: makeRequest(status: .accepted, location: "Lucia's")
        )
        await viewModel.loadBookingLink()

        XCTAssertTrue(viewModel.canBookTable)
        XCTAssertEqual(viewModel.bookingPlaceName, "Lucia's")
        XCTAssertEqual(viewModel.bookingURL?.host, "www.opentable.com")
    }

    /// The one that matters most: offering to book a table for something still being argued over.
    func testAPlanNobodyHasAgreedToOffersNothing() async {
        for status in [RequestStatus.pending, .negotiated, .countered, .declined, .cancelled] {
            let viewModel = RequestDetailViewModel(
                request: makeRequest(status: status, location: "Lucia's")
            )
            await viewModel.loadBookingLink()
            XCTAssertFalse(
                viewModel.canBookTable,
                "a \(status.rawValue) plan must not offer to book a table"
            )
        }
    }

    func testAnAgreedPlanWithNowhereToGoOffersNothing() async {
        for place in [nil, "", "   "] as [String?] {
            let viewModel = RequestDetailViewModel(
                request: makeRequest(status: .accepted, location: place)
            )
            await viewModel.loadBookingLink()
            XCTAssertFalse(viewModel.canBookTable)
            XCTAssertNil(viewModel.bookingPlaceName)
        }
    }

    /// Recorded on the tap, and carrying the party size a restaurant would care about.
    func testFollowingTheLinkRecordsAnAnonymousIntent() async {
        let viewModel = RequestDetailViewModel(
            request: makeRequest(status: .accepted, location: "Lucia's", recipients: ["b", "c"])
        )
        await viewModel.recordBookingIntent()

        let recorded = await outcomes.bookingIntents
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.groupSize, 3)
        XCTAssertEqual(recorded.first?.provider, "curated")
    }

    /// Showing the row is not intent. Only the tap is.
    func testMerelyShowingTheRowRecordsNothing() async {
        let viewModel = RequestDetailViewModel(
            request: makeRequest(status: .accepted, location: "Lucia's")
        )
        await viewModel.loadBookingLink()

        XCTAssertTrue(viewModel.canBookTable)
        let recorded = await outcomes.bookingIntents
        XCTAssertTrue(recorded.isEmpty, "an impression is not intent")
    }
}
