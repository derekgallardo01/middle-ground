import CoreLocation
import Foundation

enum LocationError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Location access is off. You can turn it on in Settings."
        case .unavailable:
            return "Couldn't get your location. Try again in a moment."
        }
    }
}

protocol LocationProviding: Sendable {
    /// One fix, now. Prompts for permission the first time.
    func currentCoordinate() async throws -> CLLocationCoordinate2D
}

/// The part of `CLLocationManager` this file uses.
///
/// A seam, so the service can be tested without the real one — which reaches for hardware, needs
/// a provisioning profile, and answers with wherever the test machine happens to be. Nothing here
/// had a test before, and this is the type that made writing one impossible.
protocol LocationManaging: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var delegate: CLLocationManagerDelegate? { get set }
    func requestWhenInUseAuthorization()
    func requestLocation()
}

extension CLLocationManager: LocationManaging {}

/// A single location fix, on demand.
///
/// `requestLocation()` rather than `startUpdatingLocation()`, deliberately: it delivers one fix
/// and stops. There is no stream to forget to cancel, nothing runs while the app is backgrounded,
/// and "When In Use" is the only authorisation ever asked for. The stricter permission is not a
/// courtesy — `Always` would require a background mode and a justification at review that this
/// feature does not have.
final class LocationService: NSObject, LocationProviding, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager: LocationManaging
    /// Guarded because the delegate callbacks arrive on the main queue while the caller may be
    /// suspended anywhere. Resuming a continuation twice is a crash, not a warning.
    private let lock = NSLock()
    private var pending: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private let timeout: Duration

    init(manager: LocationManaging = CLLocationManager(), timeout: Duration = .seconds(60)) {
        self.manager = manager
        self.timeout = timeout
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Whether anybody is actually waiting for a fix.
    ///
    /// The delegate callbacks are the system's to call, not ours, and they arrive whether or not
    /// this service asked for anything. This is what tells the difference.
    private var isWaiting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending != nil
    }

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            throw LocationError.denied
        }

        // The permission prompt can go unanswered — background the app and it simply sits there,
        // and CoreLocation reports nothing at all. `requestLocation()` guarantees exactly one
        // callback, but the prompt guarantees none, so without this the caller waits forever and
        // `shareLocation`'s spinner never stops.
        let deadline = Task { [weak self, timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(LocationError.unavailable))
        }
        defer { deadline.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            // A second tap while the first fix is still in flight would otherwise strand the
            // earlier continuation forever, and the caller's spinner with it.
            pending?.resume(throwing: LocationError.unavailable)
            pending = continuation
            lock.unlock()

            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        lock.lock()
        let continuation = pending
        pending = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    // MARK: - CLLocationManagerDelegate

    /// CoreLocation calls this **the moment the delegate is set**, not only when authorisation
    /// changes — and `LocationService` is registered unscoped in `Dependencies.swift`, so a fresh
    /// one is built every time `RequestDetailView` opens a plan.
    ///
    /// Without the guard, that meant: open any plan, and if location had ever been granted this
    /// handler called `requestLocation()` on its own. Nobody was waiting, so the fix was taken,
    /// the system location indicator appeared, and the coordinate was thrown away. The file's own
    /// promise directly above — "One fix, on demand" — was not true, and neither was the Coarse
    /// Location answer given to App Review.
    ///
    /// The parameter is deliberately ignored in favour of `self.manager`: the callback hands back
    /// the real `CLLocationManager`, which in a test is not the one this service was given.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationDidChange()
    }

    /// Split out from the delegate method so it can be called without a `CLLocationManager`.
    func authorizationDidChange() {
        guard isWaiting else { return }

        switch self.manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Only now, after the prompt is answered, is there any point asking for a fix.
            self.manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(LocationError.denied))
        case .notDetermined:
            // Still waiting on the prompt. Not a terminal state, so nothing to report — the
            // deadline in `currentCoordinate` covers a prompt that is never answered.
            break
        @unknown default:
            finish(.failure(LocationError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else {
            finish(.failure(LocationError.unavailable))
            return
        }
        finish(.success(coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(LocationError.unavailable))
    }
}

/// Fixed coordinates for previews and tests, so nothing depends on the host machine's location.
struct MockLocationService: LocationProviding {
    var coordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
    var error: LocationError?

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        if let error { throw error }
        return coordinate
    }
}
