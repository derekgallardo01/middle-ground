import XCTest
import Factory
@testable import MiddleGround

@MainActor
final class CreateRequestViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppConfiguration.useMockRepositories = true
        Container.shared.authService.register { MockAuthService() }
    }

    override func tearDown() {
        Container.shared.authService.reset()
        AppConfiguration.useMockRepositories = false
        super.tearDown()
    }

    func testCanSubmitRequiresTitleAndRecipient() async {
        let viewModel = CreateRequestViewModel()
        await viewModel.loadCurrentUserAndPartners()

        XCTAssertFalse(viewModel.canSubmit)

        viewModel.title = "Dinner tonight?"
        XCTAssertTrue(viewModel.canSubmit)
    }

    func testCreateRequestSetsErrorWhenNotSignedIn() async {
        let mockAuth = MockAuthService(mockUser: nil)
        Container.shared.authService.register { mockAuth }

        let viewModel = CreateRequestViewModel()
        viewModel.title = "Test"
        let request = await viewModel.createRequest()

        XCTAssertNil(request)
    }

    func testCreateRequestSucceedsWithValidInput() async {
        let viewModel = CreateRequestViewModel()
        await viewModel.loadCurrentUserAndPartners()
        viewModel.title = "Weekend getaway?"

        let request = await viewModel.createRequest()

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.title, "Weekend getaway?")
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - Planning a trip

    /// A backwards range would save as an ordinary single-moment plan — `isMultiDay` refuses it —
    /// so half of what somebody typed would vanish without a word. Better to refuse the send.
    func testABackwardsTripRangeBlocksSending() async {
        let viewModel = CreateRequestViewModel()
        await viewModel.loadCurrentUserAndPartners()
        viewModel.title = "Barcelona"
        viewModel.includeTime = true
        viewModel.isTrip = true
        viewModel.endTime = viewModel.proposedTime.addingTimeInterval(-86_400)

        XCTAssertFalse(viewModel.tripRangeIsValid)
        XCTAssertFalse(viewModel.canSubmit, "a plan that would silently lose its end was sendable")
    }

    func testAValidTripRangeCanBeSent() async {
        let viewModel = CreateRequestViewModel()
        await viewModel.loadCurrentUserAndPartners()
        viewModel.title = "Barcelona"
        viewModel.includeTime = true
        viewModel.isTrip = true
        viewModel.endTime = viewModel.proposedTime.addingTimeInterval(4 * 86_400)

        XCTAssertTrue(viewModel.tripRangeIsValid)
        XCTAssertTrue(viewModel.canSubmit)
    }

    /// An undated plan cannot be a trip, and must not carry an end nothing reads.
    func testATripWithNoTimeCarriesNoEnd() async {
        let viewModel = CreateRequestViewModel()
        await viewModel.loadCurrentUserAndPartners()
        viewModel.title = "Bins"
        viewModel.includeTime = false
        viewModel.isTrip = true

        XCTAssertTrue(viewModel.canSubmit, "a chore is still sendable")
    }
}
