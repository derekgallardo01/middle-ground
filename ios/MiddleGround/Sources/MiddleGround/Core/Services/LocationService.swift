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

/// A single location fix, on demand.
///
/// `requestLocation()` rather than `startUpdatingLocation()`, deliberately: it delivers one fix
/// and stops. There is no stream to forget to cancel, nothing runs while the app is backgrounded,
/// and "When In Use" is the only authorisation ever asked for. The stricter permission is not a
/// courtesy — `Always` would require a background mode and a justification at review that this
/// feature does not have.
final class LocationService: NSObject, LocationProviding, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    /// Guarded because the delegate callbacks arrive on the main queue while the caller may be
    /// suspended anywhere. Resuming a continuation twice is a crash, not a warning.
    private let lock = NSLock()
    private var pending: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            throw LocationError.denied
        }

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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Only now, after the prompt is answered, is there any point asking for a fix.
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(LocationError.denied))
        case .notDetermined:
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
