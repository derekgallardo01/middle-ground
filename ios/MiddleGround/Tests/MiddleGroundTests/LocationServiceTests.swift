import CoreLocation
import XCTest
@testable import MiddleGround

/// Taking somebody's location, and — mostly — not taking it.
///
/// This service had no tests at all, because it reached straight for `CLLocationManager`. That is
/// also why nobody noticed it asked for a fix on its own: `locationManagerDidChangeAuthorization`
/// is called by CoreLocation the moment a delegate is assigned, and `LocationService` is built
/// fresh every time a plan detail opens.
final class LocationServiceTests: XCTestCase {

    /// Records what was asked of CoreLocation, and answers on command.
    private final class FakeLocationManager: LocationManaging, @unchecked Sendable {
        var authorizationStatus: CLAuthorizationStatus = .notDetermined
        var desiredAccuracy: CLLocationAccuracy = 0
        weak var delegate: CLLocationManagerDelegate?

        private(set) var locationRequests = 0
        private(set) var authorizationRequests = 0

        func requestWhenInUseAuthorization() { authorizationRequests += 1 }
        func requestLocation() { locationRequests += 1 }

        /// Stands in for CoreLocation answering. The delegate ignores this argument, which is the
        /// only reason a real manager is not needed here.
        func answer(_ status: CLAuthorizationStatus, on service: LocationService) {
            authorizationStatus = status
            service.authorizationDidChange()
        }
    }

    // MARK: - Not taking it

    /// The whole bug, in one assertion.
    func testConstructingTheServiceDoesNotAskForALocation() {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse

        let service = LocationService(manager: manager)
        // Exactly what CoreLocation does on delegate assignment.
        service.authorizationDidChange()

        XCTAssertEqual(
            manager.locationRequests,
            0,
            "opening a plan must not take the user's location — nobody asked for it"
        )
        XCTAssertNotNil(service, "kept alive so the delegate assignment above is not optimised away")
    }

    /// An authorisation change with nobody waiting is equally not an invitation.
    func testAGrantedPromptWithNoRequestInFlightTakesNoFix() {
        let manager = FakeLocationManager()
        let service = LocationService(manager: manager)

        manager.answer(.authorizedWhenInUse, on: service)

        XCTAssertEqual(manager.locationRequests, 0)
    }

    // MARK: - Taking it when asked

    func testAnAlreadyAuthorisedRequestAsksForAFixImmediately() async throws {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let service = LocationService(manager: manager)

        async let coordinate = service.currentCoordinate()
        try await waitUntil { manager.locationRequests == 1 }

        service.locationManager(CLLocationManager(), didUpdateLocations: [
            CLLocation(latitude: 51.5, longitude: -0.12)
        ])

        let result = try await coordinate
        XCTAssertEqual(result.latitude, 51.5, accuracy: 0.0001)
        XCTAssertEqual(manager.authorizationRequests, 0, "already granted; do not prompt again")
    }

    func testAnUndecidedRequestPromptsAndThenAsksForAFix() async throws {
        let manager = FakeLocationManager()
        let service = LocationService(manager: manager)

        async let coordinate = service.currentCoordinate()
        try await waitUntil { manager.authorizationRequests == 1 }
        XCTAssertEqual(manager.locationRequests, 0, "no fix before the prompt is answered")

        manager.answer(.authorizedWhenInUse, on: service)
        try await waitUntil { manager.locationRequests == 1 }

        service.locationManager(CLLocationManager(), didUpdateLocations: [
            CLLocation(latitude: 40.7, longitude: -74.0)
        ])
        let result = try await coordinate
        XCTAssertEqual(result.longitude, -74.0, accuracy: 0.0001)
    }

    // MARK: - Failing rather than hanging

    func testDecliningThePromptFailsTheCallerRatherThanHanging() async throws {
        let manager = FakeLocationManager()
        let service = LocationService(manager: manager)

        async let coordinate = service.currentCoordinate()
        try await waitUntil { manager.authorizationRequests == 1 }

        manager.answer(.denied, on: service)

        do {
            _ = try await coordinate
            XCTFail("a declined prompt must surface as an error")
        } catch let error as LocationError {
            XCTAssertEqual(error, .denied)
        }
    }

    /// Already denied is answered without troubling CoreLocation at all.
    func testAnAlreadyDeniedRequestFailsWithoutPrompting() async {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .denied
        let service = LocationService(manager: manager)

        do {
            _ = try await service.currentCoordinate()
            XCTFail("expected denial")
        } catch {
            XCTAssertEqual(error as? LocationError, .denied)
            XCTAssertEqual(manager.authorizationRequests, 0)
            XCTAssertEqual(manager.locationRequests, 0)
        }
    }

    /// A prompt nobody ever answers produces no callback of any kind, so only the deadline can
    /// end it. Without that, `shareLocation`'s spinner runs until the screen is dismissed.
    func testAnUnansweredPromptGivesUpInsteadOfWaitingForever() async {
        let manager = FakeLocationManager()
        let service = LocationService(manager: manager, timeout: .milliseconds(50))

        do {
            _ = try await service.currentCoordinate()
            XCTFail("expected the deadline to fire")
        } catch {
            XCTAssertEqual(error as? LocationError, .unavailable)
        }
    }

    /// Two taps in flight: the first is retired, and the continuation is resumed exactly once
    /// each. Resuming twice is a crash rather than a warning, which is why this is pinned.
    func testASecondRequestRetiresTheFirstWithoutResumingItTwice() async throws {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let service = LocationService(manager: manager)

        async let first = service.currentCoordinate()
        try await waitUntil { manager.locationRequests == 1 }

        async let second = service.currentCoordinate()
        try await waitUntil { manager.locationRequests == 2 }

        service.locationManager(CLLocationManager(), didUpdateLocations: [
            CLLocation(latitude: 1, longitude: 2)
        ])

        do {
            _ = try await first
            XCTFail("the superseded request must not also succeed")
        } catch {
            XCTAssertEqual(error as? LocationError, .unavailable)
        }
        let result = try await second
        XCTAssertEqual(result.latitude, 1, accuracy: 0.0001)
    }

    func testAFailureFromCoreLocationIsReported() async throws {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let service = LocationService(manager: manager)

        async let coordinate = service.currentCoordinate()
        try await waitUntil { manager.locationRequests == 1 }

        service.locationManager(
            CLLocationManager(),
            didFailWithError: NSError(domain: kCLErrorDomain, code: CLError.network.rawValue)
        )

        do {
            _ = try await coordinate
            XCTFail("expected the failure to surface")
        } catch {
            XCTAssertEqual(error as? LocationError, .unavailable)
        }
    }

    // MARK: - Helpers

    /// `currentCoordinate` suspends, so the calls it makes land a moment after `async let`.
    private func waitUntil(
        _ condition: @Sendable () -> Bool,
        within: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now + within
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("condition not met within \(within)")
    }
}
