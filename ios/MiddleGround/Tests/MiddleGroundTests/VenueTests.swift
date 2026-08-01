import XCTest
@testable import MiddleGround

/// The venue list is editorial data written by hand in an admin form, so the interesting cases
/// are the sloppy ones: a place tagged with nothing, and a place tagged with something this
/// build has never heard of.
final class VenueTests: XCTestCase {
    func testAVenueWithNoCategoriesSuitsEveryPlan() {
        let park = Venue(name: "Prospect Park", city: "Brooklyn")

        for category in RequestCategory.allCases {
            XCTAssertTrue(park.suits(category), "should be offered for \(category.rawValue)")
        }
    }

    func testAVenueOnlySuitsWhatItIsTaggedWith() {
        let bar = Venue(name: "The Anchor", city: "Brooklyn", categories: [.friends])

        XCTAssertTrue(bar.suits(.friends))
        XCTAssertFalse(bar.suits(.family))
        XCTAssertFalse(bar.suits(.daily))
    }

    /// The failure worth preventing. An empty category list means "suits everything", so a venue
    /// whose only tag is a category this build cannot decode must not decode to empty — or a
    /// place meant for one narrow purpose starts being offered for all of them.
    func testAnUnknownCategoryDoesNotBecomeSuitsEverything() {
        let venue = Venue(name: "Somewhere", city: "Brooklyn", categories: [.unknown])

        XCTAssertFalse(venue.suits(.friends))
        XCTAssertFalse(venue.suits(.dating))
    }

    /// `.unknown` is deliberately excluded from `allCases`, so the admin form cannot tag a venue
    /// with the fallback — it exists only as a decode target.
    func testTheFallbackCategoryIsNotOfferedForTagging() {
        XCTAssertFalse(RequestCategory.allCases.contains(.unknown))
    }

    /// The name alone goes into the request. The other person already knows which city they
    /// live in, and "Lucia's, Brooklyn" reads like an address nobody asked for.
    func testOnlyTheNameGoesIntoTheRequest() {
        XCTAssertEqual(Venue(name: "Lucia's", city: "Brooklyn").locationText, "Lucia's")
    }

    func testCuratedOrderIsByRankThenName() async throws {
        let repository = MockVenueRepository(seed: [
            Venue(id: "c", name: "Zeta", city: "Brooklyn", rank: 0),
            Venue(id: "a", name: "Alpha", city: "Brooklyn", rank: 1),
            Venue(id: "b", name: "Beta", city: "Brooklyn", rank: 0)
        ])

        let ordered = try await repository.venues().map(\.name)

        XCTAssertEqual(ordered, ["Beta", "Zeta", "Alpha"])
    }
}
