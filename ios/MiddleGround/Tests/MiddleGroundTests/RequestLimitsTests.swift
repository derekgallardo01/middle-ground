import XCTest
@testable import MiddleGround

/// Only "not empty after trimming" was ever checked on user input, so a long paste reached
/// Firestore and failed against the 1 MB document limit — surfacing as a generic
/// "Failed to send request." with the typed text lost. The negotiation chain makes it worse,
/// since every message is appended to the *same* document and shares that ceiling.
@MainActor
final class RequestLimitsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppConfiguration.useMockRepositories = true
    }

    override func tearDown() {
        AppConfiguration.useMockRepositories = false
        super.tearDown()
    }

    func testClampLeavesShortTextAlone() {
        XCTAssertEqual(RequestLimits.clamp("Dinner?", to: 120), "Dinner?")
    }

    func testClampTrimsToTheLimit() {
        let long = String(repeating: "a", count: 500)
        XCTAssertEqual(RequestLimits.clamp(long, to: 120).count, 120)
    }

    /// `prefix` operates on Characters, so a multi-scalar emoji is kept whole rather than
    /// being cut into an invalid fragment.
    func testClampDoesNotSplitGraphemeClusters() {
        let flags = String(repeating: "👩‍👩‍👧‍👦", count: 50)
        let clamped = RequestLimits.clamp(flags, to: 10)
        XCTAssertEqual(clamped.count, 10)
        XCTAssertTrue(clamped.hasSuffix("👩‍👩‍👧‍👦"))
    }

    func testTitleIsClampedOnAssignment() {
        let viewModel = CreateRequestViewModel()
        viewModel.title = String(repeating: "x", count: 5_000)
        XCTAssertEqual(viewModel.title.count, RequestLimits.title)
    }

    func testDetailsIsClampedOnAssignment() {
        let viewModel = CreateRequestViewModel()
        viewModel.details = String(repeating: "x", count: 50_000)
        XCTAssertEqual(viewModel.details.count, RequestLimits.details)
    }

    /// `didSet` does not fire from an initialiser, so the init clamps explicitly. Without
    /// that, a view model seeded from a long value would bypass the cap entirely.
    func testInitialValuesAreClamped() {
        let viewModel = CreateRequestViewModel(
            title: String(repeating: "x", count: 5_000),
            details: String(repeating: "y", count: 50_000)
        )
        XCTAssertEqual(viewModel.title.count, RequestLimits.title)
        XCTAssertEqual(viewModel.details.count, RequestLimits.details)
    }

    func testCounterTextIsClamped() {
        let viewModel = RequestDetailViewModel(request: .preview)
        viewModel.counterText = String(repeating: "x", count: 50_000)
        XCTAssertEqual(viewModel.counterText.count, RequestLimits.message)
    }

    func testReportNoteIsClamped() {
        let viewModel = RequestDetailViewModel(request: .preview)
        viewModel.reportNote = String(repeating: "x", count: 50_000)
        XCTAssertEqual(viewModel.reportNote.count, RequestLimits.reportNote)
    }
}
