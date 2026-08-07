import CoreLocation
import XCTest
@testable import MiddleGround

/// Looking at a place properly, rather than picking from a name and a distance.
///
/// The chip row was the whole feature: a name, a category and a mile figure. That is enough to
/// recognise somewhere you have been and not enough to choose somewhere you have not — which is
/// exactly the case the feature exists for.
///
/// MapKit gives no photographs, so the picture is Apple's own imagery in two tiers: Look Around
/// where it exists, a map of the location where it does not. The tiers are the part worth testing —
/// a map presented as a photograph would be a small lie told on every screen without coverage.
@MainActor
final class PlaceDetailTests: XCTestCase {

    private func place(
        phone: String? = "(718) 555-0148",
        website: URL? = URL(string: "https://lucias.example.com")
    ) -> DiscoveredPlace {
        DiscoveredPlace(
            id: "x",
            name: "Lucia's",
            category: "Restaurant",
            address: "1 Main St, Brooklyn",
            latitude: 40.6782,
            longitude: -73.9442,
            distanceMiles: 0.4,
            phone: phone,
            website: website
        )
    }

    // MARK: - A number you can actually ring

    func testTheNumberIsStrippedToSomethingTelWillTake() throws {
        let url = try XCTUnwrap(place().telephoneURL)

        XCTAssertEqual(url.absoluteString, "tel:7185550148")
    }

    func testAnInternationalNumberKeepsItsPlus() throws {
        let url = try XCTUnwrap(place(phone: "+44 20 7946 0958").telephoneURL)

        XCTAssertEqual(url.absoluteString, "tel:+442079460958")
    }

    /// No number is a missing row, not a row that does nothing when tapped.
    func testNoNumberProducesNoLink() {
        XCTAssertNil(place(phone: nil).telephoneURL)
    }

    func testANumberWithNoDigitsProducesNoLink() {
        XCTAssertNil(place(phone: "call ahead").telephoneURL)
    }

    // MARK: - A map is not a photograph

    func testAMapIsNotCaptionedAsAPhotograph() {
        XCTAssertNil(
            PlaceImage.Kind.map.caption,
            "a map captioned like imagery claims to show what a place looks like"
        )
    }

    func testStreetLevelImageryIsAttributed() {
        XCTAssertEqual(PlaceImage.Kind.lookAround.caption, "Look Around")
    }

    // MARK: - Something to show

    func testEveryDiscoveredPlaceCanProduceAPicture() async {
        let provider = MockPlaceImageProvider()
        let size = CGSize(width: 80, height: 50)

        let picture = await provider.image(for: place(), size: size)

        XCTAssertNotNil(picture)
        XCTAssertEqual(picture?.image.size, size)
    }

    /// Two places in one list must not look like the same photograph.
    func testTwoPlacesDoNotGetTheSamePicture() async {
        let provider = MockPlaceImageProvider()
        let size = CGSize(width: 12, height: 12)

        let first = await provider.image(for: place(), size: size)
        var other = place()
        other = DiscoveredPlace(
            id: "y",
            name: "Copper & Oak",
            category: other.category,
            address: other.address,
            latitude: other.latitude,
            longitude: other.longitude,
            distanceMiles: other.distanceMiles,
            phone: other.phone,
            website: other.website
        )
        let second = await provider.image(for: other, size: size)

        let firstData = first?.image.pngData()
        let secondData = second?.image.pngData()
        XCTAssertNotNil(firstData)
        XCTAssertNotEqual(firstData, secondData, "every place rendered the same picture")
    }

    // MARK: - The demo data has to exercise the screen

    /// Every row of the detail sheet is conditional on the data being there. With the fixtures
    /// returning `nil` for phone and website, half the screen was invisible in every recording of
    /// it — and it looked like the design rather than like missing data.
    func testTheFixturesFillEveryRowOfTheDetail() async throws {
        let places = try await MockPlaceDiscoveryProvider().places(
            near: CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442),
            radiusMiles: 25,
            kind: .restaurant,
            matching: nil
        )

        let first = try XCTUnwrap(places.first)
        XCTAssertNotNil(first.address)
        XCTAssertNotNil(first.distanceMiles)
        XCTAssertNotNil(first.telephoneURL, "the phone row would be missing from every screenshot")
        XCTAssertNotNil(first.website)
    }

    /// Filled is not the same as right. Every fixture shared one address, one number and one
    /// domain, so the detail sheet read "1 Example Street" whichever place you opened — which
    /// looks exactly like a screen ignoring what you tapped.
    func testEachPlaceHasItsOwnDetails() async throws {
        var addresses: Set<String> = []
        var phones: Set<String> = []
        var sites: Set<String> = []
        var count = 0

        for kind in PlaceKind.allCases {
            let places = try await MockPlaceDiscoveryProvider().places(
                near: MockLocationService().coordinate,
                radiusMiles: 25,
                kind: kind,
                matching: nil
            )
            for place in places {
                count += 1
                addresses.insert(try XCTUnwrap(place.address))
                phones.insert(try XCTUnwrap(place.phone))
                sites.insert(try XCTUnwrap(place.website).absoluteString)
            }
        }

        XCTAssertGreaterThan(count, 5, "not enough fixtures to tell them apart")
        XCTAssertEqual(addresses.count, count, "two places share an address")
        XCTAssertEqual(phones.count, count, "two places share a phone number")
        XCTAssertEqual(sites.count, count, "two places share a website")
    }
}
