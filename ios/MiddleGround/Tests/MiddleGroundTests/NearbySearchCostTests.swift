import CoreLocation
import Factory
import XCTest
@testable import MiddleGround

/// What a nearby search *costs*, which nothing was measuring.
///
/// Every existing test asked whether the right places came back. None asked how many times we went
/// and got them, and the answer was: once per category tap, and once per mile of the slider. A drag
/// from 1 to 25 was twenty-four searches and twenty-four location requests, and the list flickered
/// through all of them on the way. It looked correct the whole time, because it was — just
/// twenty-four times over.
///
/// Counting is the only way to see this. A test that asserts the final results pass either way.
@MainActor
final class NearbySearchCostTests: XCTestCase {

    /// Records how often it is asked, so "one search per drag" is a measurement.
    private final class CountingDiscovery: PlaceDiscoveryProvider, @unchecked Sendable {
        private(set) var calls = 0
        private(set) var radii: [Double] = []

        func places(
            near coordinate: CLLocationCoordinate2D,
            radiusMiles: Double,
            kind: PlaceKind,
            matching term: String?
        ) async throws -> [DiscoveredPlace] {
            calls += 1
            radii.append(radiusMiles)
            return []
        }
    }

    private final class CountingLocation: LocationProviding, @unchecked Sendable {
        private(set) var fixes = 0

        func currentCoordinate() async throws -> CLLocationCoordinate2D {
            fixes += 1
            return CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442)
        }
    }

    // Non-optional and replaced in `setUp`, so the registrations below need no force unwrap and
    // no test can run against a counter that was never installed.
    private var discovery = CountingDiscovery()
    private var location = CountingLocation()

    override func setUp() {
        super.setUp()
        // Without this the view model resolves the real Firestore repositories, Firebase is not
        // configured, and every test here dies with "freed pointer was not the last allocation" —
        // a crash rather than a failure, which is why the suite reported "0 failures" while
        // xcodebuild listed five failing tests at the bottom.
        AppConfiguration.useMockRepositories = true
        Container.shared.authService.register { MockAuthService() }

        discovery = CountingDiscovery()
        location = CountingLocation()
        // Captured as locals: a capture list only takes `weak`/`unowned`, and the registration
        // must hand back *these* instances rather than build new ones, or the counters stay zero
        // and every assertion below passes for the wrong reason.
        let countingDiscovery = discovery
        let countingLocation = location
        Container.shared.placeDiscoveryProvider.register { countingDiscovery }
        Container.shared.locationService.register { countingLocation }
    }

    override func tearDown() {
        Container.shared.placeDiscoveryProvider.reset()
        Container.shared.locationService.reset()
        Container.shared.authService.reset()
        AppConfiguration.useMockRepositories = false
        super.tearDown()
    }

    private func searched() async -> CreateRequestViewModel {
        let viewModel = CreateRequestViewModel()
        viewModel.hasSearchedNearby = true
        await viewModel.findNearby()
        return viewModel
    }

    // MARK: - Location is asked for once, not once per search

    func testTheSecondSearchDoesNotAskForLocationAgain() async {
        let viewModel = await searched()

        viewModel.nearbyKind = .stay
        await viewModel.findNearby()

        XCTAssertEqual(location.fixes, 1, "changing category asked iOS for another fix")
        XCTAssertEqual(discovery.calls, 2, "but it did search again, which is the point")
    }

    /// Walking all four categories is one location request, not four.
    func testWalkingEveryCategoryAsksForLocationOnce() async {
        let viewModel = await searched()

        for kind in PlaceKind.allCases {
            viewModel.nearbyKind = kind
            await viewModel.findNearby()
        }

        XCTAssertEqual(location.fixes, 1)
    }

    // MARK: - A drag is one search

    func testDraggingTheRadiusSearchesOnceRatherThanTwentyFourTimes() async {
        let viewModel = await searched()
        let before = discovery.calls

        // What the slider does: one change per mile, as fast as a finger moves. Sequential and
        // on the main actor, because that is where SwiftUI delivers `onChange` — the debounce has
        // to hold up under the real calling pattern, not a convenient one.
        for mile in 2...25 {
            viewModel.nearbyRadiusMiles = Double(mile)
            Task { await viewModel.radiusChanged() }
            try? await Task.sleep(for: .milliseconds(5))
        }
        try? await Task.sleep(for: .milliseconds(900))

        let searches = discovery.calls - before
        XCTAssertLessThanOrEqual(searches, 3, "a single drag cost \(searches) searches")
        XCTAssertGreaterThanOrEqual(searches, 1, "the drag must end in a search")
    }

    /// The one that lands must be the radius the finger stopped on. Without cancellation the last
    /// *reply* wins, which is not the same thing and is not what anybody asked for.
    func testTheSearchThatLandsIsTheRadiusTheDragEndedOn() async {
        let viewModel = await searched()

        for mile in [4.0, 11.0, 19.0] {
            viewModel.nearbyRadiusMiles = mile
            Task { await viewModel.radiusChanged() }
            try? await Task.sleep(for: .milliseconds(10))
        }
        try? await Task.sleep(for: .milliseconds(700))

        XCTAssertEqual(discovery.radii.last, 19, "the list settled on a radius nobody chose")
    }

    // MARK: - Still off unless asked

    /// The debounce must not become a way for the radius to ask for location on its own.
    func testMovingTheRadiusBeforeAnySearchAsksForNothing() async {
        let viewModel = CreateRequestViewModel()
        XCTAssertFalse(viewModel.hasSearchedNearby)

        viewModel.nearbyRadiusMiles = 20
        await viewModel.radiusChanged()
        try? await Task.sleep(for: .milliseconds(700))

        XCTAssertEqual(location.fixes, 0, "the slider asked for location without anybody tapping")
        XCTAssertEqual(discovery.calls, 0)
    }
}
