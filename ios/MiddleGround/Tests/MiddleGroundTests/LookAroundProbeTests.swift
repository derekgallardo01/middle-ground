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

    /// The one that a distinct-coordinates test cannot catch: Apple snaps a request to the nearest
    /// photographed spot, so two places close together can still come back as one image. The only
    /// way to know is to fetch both and compare the pixels.
    func testTwoPlacesDoNotComeBackAsTheSamePhotograph() async throws {
        let here = try await MockLocationService().currentCoordinate()
        let provider = MapKitPlaceImageProvider()
        let size = CGSize(width: 200, height: 130)

        var pictures: [String: Data] = [:]
        for kind in PlaceKind.allCases {
            let places = try await MockPlaceDiscoveryProvider().places(
                near: here, radiusMiles: 25, kind: kind, matching: nil
            )
            guard let first = places.first else { continue }
            guard let picture = await provider.image(for: first, size: size),
                  let data = picture.image.pngData() else {
                throw XCTSkip("No imagery available in this environment.")
            }
            pictures[first.name] = data
        }

        XCTAssertEqual(pictures.count, PlaceKind.allCases.count)
        XCTAssertEqual(
            Set(pictures.values).count,
            pictures.count,
            "\(pictures.keys.sorted()) — two of these show the identical photograph"
        )
    }

    // MARK: - Does Apple tell us what time it is there?

    /// A trip abroad can only say a true thing if the plan knows its own zone, and the only place
    /// that can come from is the search result. A locally-built `MKMapItem` has no `timeZone`, so
    /// this asks a real search rather than assuming the field is populated.
    func testASearchResultAbroadKnowsItsTimeZone() async throws {
        let barcelona = CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restaurant"
        request.region = MKCoordinateRegion(
            center: barcelona, latitudinalMeters: 3_000, longitudinalMeters: 3_000
        )

        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch {
            throw XCTSkip("No network for a live search: \(error)")
        }

        guard let first = response.mapItems.first else {
            throw XCTSkip("Nothing came back to inspect.")
        }

        let zone = try XCTUnwrap(
            first.timeZone,
            "search results carry no time zone — a plan abroad cannot know its own hour"
        )
        XCTAssertEqual(
            zone.identifier,
            "Europe/Madrid",
            "a restaurant in Barcelona reported \(zone.identifier)"
        )
    }

    /// And it survives the mapping into our own type.
    func testTheZoneSurvivesIntoADiscoveredPlace() async throws {
        let barcelona = CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restaurant"
        request.region = MapKitPlaceDiscoveryProvider.region(around: barcelona, radiusMiles: 2)

        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch {
            throw XCTSkip("No network for a live search.")
        }

        let places = MapKitPlaceDiscoveryProvider.places(
            from: response.mapItems, origin: barcelona, radiusMiles: 2
        )
        guard let first = places.first else { throw XCTSkip("Nothing within the radius.") }

        XCTAssertEqual(first.timeZoneIdentifier, "Europe/Madrid")
    }

    // MARK: - Can a typed place name tell us its zone?

    /// The hole the time-zone work left. `findNearby` searches from the user's *current*
    /// coordinate, so a trip to Barcelona composed from a sofa in Brooklyn finds no Barcelona
    /// venues — and the plan's zone stays nil for exactly the case the field exists for. Typing
    /// the place is the only route left, so this asks whether a typed name can supply a zone.
    func testGeocodingATypedPlaceNameYieldsItsTimeZone() async throws {
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await CLGeocoder().geocodeAddressString("Barcelona, Spain")
        } catch {
            throw XCTSkip("No network for geocoding: \(error)")
        }

        let first = try XCTUnwrap(placemarks.first, "nothing came back for Barcelona")
        let zone = try XCTUnwrap(
            first.timeZone,
            "a geocoded placemark carries no time zone — a typed destination cannot know its hour"
        )
        XCTAssertEqual(zone.identifier, "Europe/Madrid")
    }

    /// And a name that is not a place must not confidently return somewhere.
    func testGeocodingNonsenseDoesNotInventAPlace() async throws {
        do {
            let placemarks = try await CLGeocoder()
                .geocodeAddressString("zzqx not a real place at all 12345")
            XCTAssertTrue(
                placemarks.isEmpty,
                "geocoding invented \(placemarks.first?.name ?? "somewhere") for nonsense"
            )
        } catch {
            // A "no result" error is the correct answer, and is what this usually returns.
            XCTAssertTrue(true)
        }
    }
}
