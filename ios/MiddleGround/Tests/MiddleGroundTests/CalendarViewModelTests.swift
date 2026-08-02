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
        XCTAssertFalse(viewModel.events.isEmpty, "mock repository seeds dated requests")
    }

    func testEventsForDateFiltersByDay() async throws {
        let viewModel = CalendarViewModel()
        await viewModel.loadCurrentUser()
        await viewModel.loadEvents()

        // Anchor on a date we know has an event, so this cannot pass vacuously.
        let anchor = try XCTUnwrap(Request.preview.proposedTime, "fixture must have a proposed time")
        let matching = viewModel.events(for: anchor)

        XCTAssertFalse(matching.isEmpty, "the seeded request falls on this day")
        for event in matching {
            XCTAssertTrue(Calendar.current.isDate(try XCTUnwrap(event.proposedTime), inSameDayAs: anchor))
        }

        XCTAssertTrue(viewModel.events(for: .distantPast).isEmpty, "no events on an unrelated day")
    }
}
