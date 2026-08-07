import CoreLocation
import MapKit
import XCTest
@testable import MiddleGround

/// Finding somewhere to go.
///
/// `MKLocalSearch` itself needs a network and cannot be tested here, so the mapping is pure and
/// static and everything that decides what a person sees is exercised directly: the radius filter,
/// the ordering, the cap, and the words. `MKMapItem` is constructible, which is the whole reason
/// that logic lives in `places(from:origin:radiusMiles:)` rather than inline in the search.
///
/// The filter is the one worth having. `MKCoordinateRegion` is a square and a radius is a circle,
/// so a five-mile search asks a region that reaches seven miles at the corners — without the
/// filter, "within 5 miles" quietly means "within 7 diagonally", which is the sort of claim this
/// codebase keeps finding.
final class PlaceDiscoveryTests: XCTestCase {

    private let brooklyn = CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442)

    /// Roughly `miles` due north, which is the easy direction to reason about: a degree of
    /// latitude is about 69 miles everywhere.
    private func north(of origin: CLLocationCoordinate2D, miles: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: origin.latitude + (miles / 69.0), longitude: origin.longitude)
    }

    private func item(
        _ name: String,
        at coordinate: CLLocationCoordinate2D,
        category: MKPointOfInterestCategory? = .restaurant
    ) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.pointOfInterestCategory = category
        return mapItem
    }

    // MARK: - The radius actually means something

    func testSomewhereBeyondTheRadiusIsDropped() {
        let items = [
            item("Near", at: north(of: brooklyn, miles: 1)),
            item("Far", at: north(of: brooklyn, miles: 9))
        ]

        let places = MapKitPlaceDiscoveryProvider.places(from: items, origin: brooklyn, radiusMiles: 5)

        XCTAssertEqual(places.map(\.name), ["Near"], "a 5-mile search returned somewhere 9 miles away")
    }

    /// The square-region problem, stated as a test: a place at the corner of the region is inside
    /// the box and outside the circle.
    func testTheCornerOfTheSearchRegionIsNotWithinTheRadius() {
        let corner = CLLocationCoordinate2D(
            latitude: brooklyn.latitude + (4.5 / 69.0),
            longitude: brooklyn.longitude + (4.5 / 52.0)   // ~4.5 miles east at this latitude
        )
        let places = MapKitPlaceDiscoveryProvider.places(
            from: [item("Corner", at: corner)], origin: brooklyn, radiusMiles: 5
        )

        XCTAssertTrue(places.isEmpty, "6.4 miles diagonally is not within 5 miles")
    }

    func testTheFullTwentyFiveMilesIsUsable() {
        // Yelp's 40,000 m ceiling — 24.85 miles — was the only reason 25 was ever awkward.
        let places = MapKitPlaceDiscoveryProvider.places(
            from: [item("Just inside", at: north(of: brooklyn, miles: 24.5))],
            origin: brooklyn,
            radiusMiles: 25
        )
        XCTAssertEqual(places.count, 1)
    }

    // MARK: - Order and volume

    func testNearestComesFirst() {
        let items = [
            item("Third", at: north(of: brooklyn, miles: 3)),
            item("First", at: north(of: brooklyn, miles: 0.5)),
            item("Second", at: north(of: brooklyn, miles: 1.5))
        ]

        let places = MapKitPlaceDiscoveryProvider.places(from: items, origin: brooklyn, radiusMiles: 10)

        XCTAssertEqual(places.map(\.name), ["First", "Second", "Third"])
    }

    func testTheListIsCappedSoAChipRowStaysAShortcut() {
        let items = (0..<40).map { index in
            item("Place \(index)", at: north(of: brooklyn, miles: Double(index) * 0.1 + 0.1))
        }

        let places = MapKitPlaceDiscoveryProvider.places(from: items, origin: brooklyn, radiusMiles: 25)

        XCTAssertEqual(places.count, MapKitPlaceDiscoveryProvider.resultLimit)
        XCTAssertEqual(places.first?.name, "Place 0", "the cap must keep the nearest, not the first 15 given")
    }

    /// The nameless guard in `places(from:)` cannot be exercised from here: assigning `nil` to
    /// `MKMapItem.name` does not stick — it falls back to a name derived from the placemark — so a
    /// test asserting otherwise fails against Apple rather than against us. The guard stays
    /// because the type says `String?` and a chip with no label is untappable on purpose; this
    /// note is here so nobody adds that test again and concludes the guard is broken.
    func testEveryPlaceReturnedHasSomethingToShowOnAChip() {
        let places = MapKitPlaceDiscoveryProvider.places(
            from: [item("Lucia's", at: north(of: brooklyn, miles: 1))],
            origin: brooklyn,
            radiusMiles: 5
        )

        XCTAssertFalse(places.isEmpty)
        for place in places {
            XCTAssertFalse(place.name.isEmpty)
        }
    }

    // MARK: - What it reads like

    func testDistanceIsRoundedToSomethingAPersonWouldSay() {
        let places = MapKitPlaceDiscoveryProvider.places(
            from: [item("Lucia's", at: north(of: brooklyn, miles: 0.42))],
            origin: brooklyn,
            radiusMiles: 5
        )

        XCTAssertEqual(places.first?.distanceMiles, 0.4)
    }

    func testTheCategoryIsReadableRatherThanAnIdentifier() {
        XCTAssertEqual(MapKitPlaceDiscoveryProvider.readableCategory(.restaurant), "Restaurant")
        XCTAssertEqual(MapKitPlaceDiscoveryProvider.readableCategory(.movieTheater), "Movie Theater")
        XCTAssertFalse(
            MapKitPlaceDiscoveryProvider.readableCategory(.nightlife).contains("MKPOICategory"),
            "nobody should read a raw identifier off a chip"
        )
    }

    func testTheSubtitleReadsAsAPhrase() {
        let places = MapKitPlaceDiscoveryProvider.places(
            from: [item("Lucia's", at: north(of: brooklyn, miles: 0.4))],
            origin: brooklyn,
            radiusMiles: 5
        )

        XCTAssertEqual(places.first?.subtitle, "Restaurant · 0.4 mi")
    }

    /// A place with neither category nor distance should not render a stray separator.
    func testASubtitleWithNothingToSayIsEmpty() {
        let place = DiscoveredPlace(
            id: "x", name: "Somewhere", category: nil, address: nil,
            latitude: 0, longitude: 0, distanceMiles: nil, phone: nil, website: nil
        )
        XCTAssertEqual(place.subtitle, "")
    }

    // MARK: - Which categories each kind searches

    func testDinnerAcceptsACafeAndABakery() {
        // A town without a literal `.restaurant` should not look like a town without food.
        XCTAssertEqual(PlaceKind.restaurant.pointOfInterestCategories, [.restaurant, .cafe, .bakery])
    }

    func testEveryKindSearchesForSomethingAndCanBeLabelled() {
        for kind in PlaceKind.allCases {
            XCTAssertFalse(kind.pointOfInterestCategories.isEmpty, "\(kind) searches for nothing")
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertFalse(kind.symbolName.isEmpty)
            XCTAssertFalse(kind.searchTerm.isEmpty)
        }
    }

    /// MapKit cannot know what is *on* tonight; it knows where events happen. The distinction is
    /// why Ticketmaster still exists in this feature.
    func testEventsSearchVenuesRatherThanListings() {
        XCTAssertTrue(PlaceKind.event.pointOfInterestCategories.contains(.theater))
        XCTAssertTrue(PlaceKind.event.pointOfInterestCategories.contains(.stadium))
        // `.musicVenue` is iOS 18+, so it is added where available rather than assumed — the
        // deployment target is 17 and the list has to be useful there too.
        if #available(iOS 18.0, *) {
            XCTAssertTrue(PlaceKind.event.pointOfInterestCategories.contains(.musicVenue))
        }
    }

    // MARK: - Looking it up elsewhere

    func testEveryLookupProducesAUsableLink() throws {
        let place = DiscoveredPlace(
            id: "x", name: "Lucia's Pizza", category: "Restaurant", address: "1 Main St",
            latitude: 40.6782, longitude: -73.9442, distanceMiles: 0.4, phone: nil, website: nil
        )

        for lookup in PlaceLookup.allCases {
            let url = try XCTUnwrap(lookup.url(for: place), "\(lookup) produced no link")
            XCTAssertTrue(url.absoluteString.contains("Lucia"), "\(lookup) lost the name")
            XCTAssertFalse(url.absoluteString.contains(" "), "\(lookup) left an unescaped space")
        }
    }

    func testTheRegionIsWideEnoughToContainTheRadius() {
        let region = MapKitPlaceDiscoveryProvider.region(around: brooklyn, radiusMiles: 5)

        // Measured rather than approximated. The `miles / 69.0` shorthand used elsewhere in this
        // file is fine for placing a fixture and not fine for an assertion — it is off by enough
        // to fail a boundary by 0.0001 of a mile, which says nothing about the code.
        let centre = CLLocation(latitude: brooklyn.latitude, longitude: brooklyn.longitude)
        let northEdge = CLLocation(
            latitude: brooklyn.latitude + region.span.latitudeDelta / 2,
            longitude: brooklyn.longitude
        )
        let halfSpanMiles = centre.distance(from: northEdge) / 1609.344

        XCTAssertGreaterThanOrEqual(halfSpanMiles, 5, "the search cannot see as far as it claims")
    }
}
