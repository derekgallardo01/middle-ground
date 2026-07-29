import XCTest
import Factory
@testable import MiddleGround

@MainActor
final class HomeViewModelTests: XCTestCase {
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
    
    func testLoadCurrentUserPopulatesUser() async {
        let viewModel = HomeViewModel()
        await viewModel.loadCurrentUser()
        
        XCTAssertNotNil(viewModel.currentUser)
        XCTAssertEqual(viewModel.currentUser?.name, "Test User")
    }
    
    func testLoadRequestsPopulatesRequests() async {
        let viewModel = HomeViewModel()
        await viewModel.loadCurrentUser()
        await viewModel.loadRequests()
        
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testLoadStatsPopulatesStats() async {
        let viewModel = HomeViewModel()
        await viewModel.loadCurrentUser()
        await viewModel.loadStats()
        
        XCTAssertGreaterThanOrEqual(viewModel.stats.level, 1)
    }
}
