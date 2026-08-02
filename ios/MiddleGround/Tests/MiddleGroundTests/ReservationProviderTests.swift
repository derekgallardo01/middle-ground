import XCTest
@testable import MiddleGround

/// The seam exists so a partnership is a one-line swap. These tests pin the two things that would
/// make that false: a provider that lies about what it can do, and a link that drops the party
/// size or time we already knew.
final class ReservationProviderTests: XCTestCase {
    private func makeProvider() -> CuratedVenueReservationProvider {
        CuratedVenueReservationProvider(venues: MockVenueRepository())
    }

    func testItDeclaresOnlyWhatItCanActuallyDo() {
        let provider = makeProvider()
        XCTAssertTrue(provider.capabilities.contains(.search))
        XCTAssertTrue(provider.capabilities.contains(.link))
        XCTAssertFalse(
            provider.capabilities.contains(.booking),
            "v1 cannot hold a table, and a screen that trusts this must not be told otherwise"
        )
    }

    /// A caller that ignores `capabilities` should get an error, not a silent no-op.
    func testBookingRefusesRatherThanPretending() async {
        let provider = makeProvider()
        let venue = ReservableVenue(
            name: "Lucia's", city: "Brooklyn", providerID: "curated", providerVenueID: "v1"
        )
        do {
            _ = try await provider.book(venue, partySize: 2, at: Date())
            XCTFail("v1 must not claim to have booked anything")
        } catch {
            XCTAssertEqual(error as? ReservationError, .notSupported)
        }
    }

    func testSearchNarrowsToTheCityWhenOneIsGiven() async throws {
        let results = try await makeProvider().search(near: "Brooklyn", partySize: 2, at: nil)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.city == "Brooklyn" })
        XCTAssertTrue(results.allSatisfy { $0.providerID == "curated" })
    }

    /// An unrecognised place must not empty the list — somewhere is better than nowhere when the
    /// user has already agreed to go out.
    func testAnUnknownLocationFallsBackToTheWholeList() async throws {
        let provider = makeProvider()
        let all = try await provider.search(near: nil, partySize: 2, at: nil)
        let unknown = try await provider.search(near: "Reykjavik", partySize: 2, at: nil)
        XCTAssertEqual(unknown.count, all.count)
    }

    func testTheBookingLinkCarriesThePartySizeAndTime() throws {
        let provider = makeProvider()
        let venue = ReservableVenue(
            name: "Lucia's", city: "Brooklyn", providerID: "curated", providerVenueID: "v1"
        )
        let time = Date(timeIntervalSince1970: 1_785_000_000)
        let url = try XCTUnwrap(provider.bookingURL(for: venue, partySize: 4, at: time))
        let items = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )

        XCTAssertEqual(url.host, "www.opentable.com")
        XCTAssertEqual(items.first { $0.name == "covers" }?.value, "4")
        XCTAssertEqual(items.first { $0.name == "term" }?.value, "Lucia's")
        XCTAssertNotNil(
            items.first { $0.name == "dateTime" }?.value,
            "the point of the link is that nobody re-enters what we already know"
        )
    }

    func testATimelessPlanStillProducesALink() throws {
        let venue = ReservableVenue(
            name: "The Anchor", city: "Brooklyn", providerID: "curated", providerVenueID: "v3"
        )
        let url = try XCTUnwrap(makeProvider().bookingURL(for: venue, partySize: 2, at: nil))
        XCTAssertFalse(url.absoluteString.contains("dateTime"))
    }
}
