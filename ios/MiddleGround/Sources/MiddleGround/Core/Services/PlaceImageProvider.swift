import CoreLocation
import MapKit
import SwiftUI

/// A picture of somewhere, without a photo API.
///
/// MapKit returns no photographs — `MKMapItem` carries a name, a category, an address and a phone
/// number, and nothing you can look at. The usual answer is a venue-photo API, which means a key in
/// the binary, a bill, and telling people their coordinate goes to somebody else. All three were
/// avoided deliberately when discovery moved on-device, and a picture is not worth undoing that.
///
/// So the imagery is Apple's own, in two tiers:
///
/// 1. **Look Around** — street-level photography of the actual place. This is a real picture of the
///    building somebody is deciding whether to walk to.
/// 2. **A map snapshot** — where Look Around has no coverage, which is most of the world outside
///    cities. Not a photograph, and it does not pretend to be: it shows where the place *is*.
///
/// Both are rendered by Apple from data the device already has rights to. No key, no third party,
/// no disclosure that the privacy policy does not already make.
protocol PlaceImageProviding: Sendable {
    func image(for place: DiscoveredPlace, size: CGSize) async -> PlaceImage?
}

/// What came back, and what it actually is — so the UI can caption it honestly.
struct PlaceImage: Sendable {
    let image: UIImage
    let kind: Kind

    enum Kind: Sendable {
        /// Apple's street-level photography of this spot.
        case lookAround
        /// A map of where it is. Shown when there is no photography, never captioned as a photo.
        case map

        var caption: String? {
            switch self {
            case .lookAround: return "Look Around"
            case .map: return nil
            }
        }
    }
}

struct MapKitPlaceImageProvider: PlaceImageProviding {

    func image(for place: DiscoveredPlace, size: CGSize) async -> PlaceImage? {
        if let lookAround = await lookAround(at: place.coordinate, size: size) {
            return PlaceImage(image: lookAround, kind: .lookAround)
        }
        if let map = await map(at: place.coordinate, size: size) {
            return PlaceImage(image: map, kind: .map)
        }
        return nil
    }

    /// Street-level photography, where Apple has it.
    ///
    /// `MKLookAroundSceneRequest` answers `nil` for most of the world rather than throwing, which
    /// is why the map tier exists and why a failure here is not worth surfacing: "no photo" is a
    /// normal answer, not an error somebody needs to read.
    private func lookAround(at coordinate: CLLocationCoordinate2D, size: CGSize) async -> UIImage? {
        do {
            let request = MKLookAroundSceneRequest(coordinate: coordinate)
            guard let scene = try await request.scene else { return nil }

            let options = MKLookAroundSnapshotter.Options()
            options.size = size
            let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
            return try await snapshotter.snapshot.image
        } catch {
            return nil
        }
    }

    /// Where it is, when there is no picture of what it looks like.
    private func map(at coordinate: CLLocationCoordinate2D, size: CGSize) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 400,
            longitudinalMeters: 400
        )
        options.size = size
        options.pointOfInterestFilter = .includingAll

        do {
            return try await MKMapSnapshotter(options: options).start().image
        } catch {
            return nil
        }
    }
}

/// A flat colour, so previews and UI tests neither hit the network nor depend on Apple having
/// photographed the fixture's coordinates.
struct MockPlaceImageProvider: PlaceImageProviding {
    var kind: PlaceImage.Kind = .lookAround

    func image(for place: DiscoveredPlace, size: CGSize) async -> PlaceImage? {
        // A beat, so the placeholder is a state somebody sees rather than a frame nobody does.
        try? await Task.sleep(for: .milliseconds(250))

        let renderer = UIGraphicsImageRenderer(size: size)
        let drawn = renderer.image { context in
            // Keyed off the name, so two places in one list do not look like the same photograph.
            let hue = Double(abs(place.name.hashValue) % 360) / 360.0
            UIColor(hue: hue, saturation: 0.35, brightness: 0.78, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return PlaceImage(image: drawn, kind: kind)
    }
}
