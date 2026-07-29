import XCTest
import Factory
@testable import MiddleGround

@MainActor
final class CalendarViewModelTests: XCTestCase {
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
    
    func testLoadEventsRequiresUser() async {
        let mockAuth = MockAuthService(mockUser: nil)
        Container.shared.authService.register { mockAuth }
        
        let viewModel = CalendarViewModel()
        await viewModel.loadEvents()
        
        XCTAssertEqual(viewModel.errorMessage, "Not signed in.")
        XCTAssertTrue(viewModel.events.isEmpty)
    }
    
    func testLoadEventsForSignedInUser() async {
        let viewModel = CalendarViewModel()
        await viewModel.loadCurrentUser()
        await viewModel.loadEvents()
        
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    func testEventsForDateFiltersByDay() async {
        let viewModel = CalendarViewModel()
        await viewModel.loadCurrentUser()
        await viewModel.loadEvents()
        
        let today = Date()
        let todaysEvents = viewModel.events(for: today)
        
        for event in todaysEvents {
            XCTAssertTrue(Calendar.current.isDate(event.proposedTime ?? Date.distantPast, inSameDayAs: today))
        }
    }
}
