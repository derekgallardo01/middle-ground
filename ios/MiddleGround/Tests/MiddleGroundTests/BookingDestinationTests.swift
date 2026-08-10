import XCTest
@testable import MiddleGround

/// Links to services that would not give us an API.
///
/// OpenTable declined; Resy, Airbnb and Kayak have no public API to decline with. A public search
/// URL needs nobody's permission, so what ships is a well-addressed link rather than an
/// integration — and the failure mode of a well-addressed link is quiet. A renamed query parameter
/// upstream produces a page that loads perfectly and ignores everything it was told, which is
/// worse than a 404 because nothing looks wrong.
///
/// These assert the parts a person would notice were missing: the party size, the dates, and the
/// place surviving the trip into a path segment.
final class BookingDestinationTests: XCTestCase {

    private func query(_ url: URL?) throws -> [String: String] {
        let url = try XCTUnwrap(url)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }) { first, _ in first }
    }

    /// 7:30pm on a Saturday, in whatever zone this machine is in.
    ///
    /// Built from wall-clock components rather than an epoch, because the property under test is
    /// exactly that the link echoes the hour a person is looking at — an epoch would make the
    /// expectation depend on where the test happens to run.
    private var saturdayEvening: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 12
        components.hour = 19
        components.minute = 30
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    // MARK: - Which service suits which plan

    func testARestaurantIsNotOfferedAnAirbnb() {
        XCTAssertEqual(BookingDestination.options(for: .restaurant), [.openTable, .resy])
        XCTAssertEqual(BookingDestination.options(for: .bar), [.openTable, .resy])
    }

    func testAStayIsNotOfferedATable() {
        XCTAssertEqual(BookingDestination.options(for: .stay), [.kayak, .airbnb])
    }

    /// An event already carries its own ticket link from the source, so offering a table for it
    /// would send somebody somewhere unrelated.
    func testAnEventOffersNothingToBook() {
        XCTAssertTrue(BookingDestination.options(for: .event).isEmpty)
    }

    // MARK: - Restaurants

    func testOpenTableCarriesThePartySizeAndTime() throws {
        let url = BookingLinkBuilder.openTable(place: "Lucia's", partySize: 4, at: saturdayEvening)
        let items = try query(url)

        XCTAssertEqual(items["term"], "Lucia's")
        XCTAssertEqual(items["covers"], "4")
        // The hour the app shows, not UTC. This assertion is the whole point: the previous test
        // for this link only checked `dateTime` was *present*, so it passed happily while every
        // link outside GMT named the wrong evening.
        XCTAssertEqual(items["dateTime"], "2026-09-12T19:30:00")
    }

    func testResyCarriesTheSeatsAndTheDay() throws {
        let url = BookingLinkBuilder.resy(place: "Lucia's", partySize: 2, at: saturdayEvening)
        let items = try query(url)

        XCTAssertEqual(items["query"], "Lucia's")
        XCTAssertEqual(items["seats"], "2")
        // Resy's search reads the day; the hour is chosen on their page, so sending one would be
        // pretending we had set something we had not.
        XCTAssertEqual(items["date"], "2026-09-12")
        XCTAssertNil(items["time"])
    }

    func testAPlanWithNoTimeStillProducesALink() throws {
        let openTable = BookingLinkBuilder.openTable(place: "Lucia's", partySize: 2, at: nil)
        let resy = BookingLinkBuilder.resy(place: "Lucia's", partySize: 2, at: nil)

        XCTAssertNil(try query(openTable)["dateTime"])
        XCTAssertNil(try query(resy)["date"])
        XCTAssertEqual(try query(openTable)["term"], "Lucia's")
    }

    /// A party size of zero would be nonsense to send, and every one of these has a minimum of one.
    func testAPartySizeIsNeverBelowOne() throws {
        XCTAssertEqual(try query(BookingLinkBuilder.openTable(place: "X", partySize: 0, at: nil))["covers"], "1")
        let kayak = BookingLinkBuilder.kayak(
            place: "Brooklyn", checkIn: saturdayEvening, checkOut: saturdayEvening, guests: 0
        )
        XCTAssertTrue(try XCTUnwrap(kayak).absoluteString.hasSuffix("1adults"))
    }

    // MARK: - Stays

    func testKayakPutsTheDatesInThePath() throws {
        let checkOut = saturdayEvening.addingTimeInterval(2 * 24 * 3600)
        let url = try XCTUnwrap(BookingLinkBuilder.kayak(
            place: "Brooklyn", checkIn: saturdayEvening, checkOut: checkOut, guests: 2
        ))

        XCTAssertEqual(
            url.absoluteString,
            "https://www.kayak.com/hotels/brooklyn/2026-09-12/2026-09-14/2adults"
        )
    }

    func testAirbnbCarriesTheDatesAndGuests() throws {
        let checkOut = saturdayEvening.addingTimeInterval(2 * 24 * 3600)
        let url = BookingLinkBuilder.airbnb(
            place: "Brooklyn", checkIn: saturdayEvening, checkOut: checkOut, guests: 3
        )
        let items = try query(url)

        XCTAssertEqual(items["checkin"], "2026-09-12")
        XCTAssertEqual(items["checkout"], "2026-09-14")
        XCTAssertEqual(items["adults"], "3")
        XCTAssertTrue(try XCTUnwrap(url).path.contains("brooklyn"))
    }

    // MARK: - Slugs, which is where a path-segment link actually breaks

    func testAPlaceWithPunctuationSurvivesThePath() {
        XCTAssertEqual(BookingLinkBuilder.slugify("New York, NY"), "new-york-ny")
        XCTAssertEqual(BookingLinkBuilder.slugify("St. John's"), "st-john-s")
        XCTAssertEqual(BookingLinkBuilder.slugify("  spaced   out  "), "spaced-out")
    }

    /// Percent-encoding an accented character in a *path segment* resolves to nothing on both
    /// sites, so the fold has to happen before the URL is built rather than being left to
    /// `URLComponents`.
    func testAnAccentedPlaceIsFoldedRatherThanEncoded() {
        XCTAssertEqual(BookingLinkBuilder.slugify("Málaga"), "malaga")
        XCTAssertEqual(BookingLinkBuilder.slugify("Zürich"), "zurich")
        XCTAssertFalse(BookingLinkBuilder.slugify("Málaga").contains("%"))
    }

    func testAPlaceThatSlugifiesToNothingProducesNoLink() {
        XCTAssertNil(BookingLinkBuilder.kayak(
            place: "!!!", checkIn: Date(), checkOut: Date(), guests: 2
        ))
        XCTAssertNil(BookingLinkBuilder.airbnb(
            place: "   ", checkIn: Date(), checkOut: Date(), guests: 2
        ))
    }

    // MARK: - Every destination is describable

    func testEveryDestinationHasANameAndASymbol() {
        for destination in BookingDestination.allCases {
            XCTAssertFalse(destination.displayName.isEmpty)
            XCTAssertFalse(destination.symbolName.isEmpty)
        }
    }
}
