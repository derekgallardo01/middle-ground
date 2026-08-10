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
    // MARK: - Sharing that reached nobody

    /// Blocking out a day is a message to other people. When every write fails, the day looked
    /// blocked on this phone and nowhere else — `try?` swallowed it, so nothing said so and the
    /// user had every reason to believe their group could see it.
    func testADayThatCouldNotBeSharedIsNotLeftLookingShared() async {
        Container.shared.availabilityRepository.register { UnwritableAvailabilityRepository() }
        defer { Container.shared.availabilityRepository.reset() }

        let viewModel = CalendarViewModel()
        await viewModel.loadCurrentUser()
        await viewModel.loadAvailability()
        XCTAssertFalse(viewModel.groups.isEmpty, "the fixture user is in at least one group")

        let day = Date()
        await viewModel.toggleUnavailable(on: day)

        XCTAssertFalse(
            viewModel.isMarkedUnavailable(on: day),
            "nothing was written anywhere, so the day must not stay marked"
        )
        XCTAssertEqual(
            viewModel.availabilityErrorMessage,
            "Couldn't share that. Check your connection and try again."
        )
        XCTAssertNil(viewModel.errorMessage, "a failed write must not replace the whole calendar")
    }

    /// One group failing is not the same thing: it did reach somebody, so the local state stands.
    func testOneGroupFailingStillCounts() async {
        let viewModel = CalendarViewModel()
        await viewModel.loadCurrentUser()
        await viewModel.loadAvailability()

        let day = Date()
        await viewModel.toggleUnavailable(on: day)

        XCTAssertTrue(viewModel.isMarkedUnavailable(on: day))
        XCTAssertNil(viewModel.availabilityErrorMessage)
    }
}

/// Reads fine, never writes — the offline case for a screen whose whole job is telling other
/// people something.
actor UnwritableAvailabilityRepository: AvailabilityRepository {
    func availability(forGroup groupID: String) async throws -> [SharedAvailability] { [] }

    nonisolated func observeAvailability(forGroup groupID: String) -> AsyncStream<[SharedAvailability]> {
        AsyncStream { $0.finish() }
    }

    func save(_ availability: SharedAvailability, forGroup groupID: String) async throws {
        throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
    }
}
