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
}
