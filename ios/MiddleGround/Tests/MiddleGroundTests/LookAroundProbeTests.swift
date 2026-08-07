import CoreLocation
import MapKit
import XCTest
@testable import MiddleGround

/// Does Apple actually have a picture of a place, and does it reach us?
///
/// Every place detail filmed so far showed the map tier, which is the fallback. That could mean
/// Look Around has no coverage at the fixture coordinates, or that the request fails in the
/// simulator, or that the code never asks — and the difference decides whether "show photos of the
/// place" is a bug to fix or an API to buy.
///
/// Needs a network and talks to Apple, so it skips rather than fails when there is no answer — it
/// can live in the suite without making it flaky, while still catching the thing that matters:
/// demo coordinates drifting off coverage, which is invisible because the fallback works.
final class LookAroundProbeTests: XCTestCase {

    /// Times Square. If anywhere on earth has Look Around coverage, it is here.
    private let timesSquare = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

    func testWhetherAppleHasStreetImageryForACoveredCoordinate() async throws {
        let scene: MKLookAroundScene?
        do {
            scene = try await MKLookAroundSceneRequest(coordinate: timesSquare).scene
        } catch {
            throw XCTSkip("Look Around request failed outright: \(error)")
        }

        guard let scene else {
            throw XCTSkip("No Look Around scene at Times Square — coverage or simulator limit.")
        }

        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(width: 320, height: 200)
        let image = try await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image

        XCTAssertGreaterThan(image.size.width, 0, "a scene came back but produced no picture")
    }

    /// What the app would actually show for the place the tour opens first.
    func testWhichTierTheFirstFixturePlaceGets() async throws {
        // Wherever the mock says the phone is — the same coordinate the app would search from.
        // Hardcoding one here is how this probe reported the old spot after it had been moved.
        let here = try await MockLocationService().currentCoordinate()
        let places = try await MockPlaceDiscoveryProvider().places(
            near: here,
            radiusMiles: 5,
            kind: .restaurant,
            matching: nil
        )
        let place = try XCTUnwrap(places.first)

        let picture = await MapKitPlaceImageProvider().image(
            for: place,
            size: CGSize(width: 320, height: 200)
        )

        guard let picture else {
            throw XCTSkip("No picture at all — no network in this environment.")
        }

        // The fixtures must sit where Apple has photographed, or every screenshot and every
        // recording quietly shows a map instead of a place. They did for a while: the demo
        // location was 40.7128,-74.0060, which has no coverage, and the fallback did its job so
        // well that nothing looked broken.
        XCTAssertEqual(
            picture.kind,
            .lookAround,
            "'\(place.name)' has no street imagery — the demo location has drifted off coverage"
        )
    }
}
