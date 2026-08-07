import CoreLocation
import Foundation
import MapKit

/// Somewhere to go, found on the device.
///
/// The moment this serves is *before* a plan exists. `ReservationProvider` handles the moment
/// after — a plan is agreed, here is a link to book it — and the two are deliberately separate
/// protocols rather than one widened: booking is party sizes and tables, discovery is a radius and
/// a category, and a hotel or a gig fits neither shape.
///
/// It searches through Apple's `MKLocalSearch`, which matters for a reason beyond it being free:
/// **the coordinate never leaves Apple's stack.** There is no key to leak, no server to proxy
/// through, and nothing to disclose about sending someone's whereabouts to a third party. The
/// alternative — Yelp — retired its free tier at $229 a month, and even paid would have meant
/// telling people their location goes somewhere else.
///
/// What it gives up is ratings, prices and photos. Those are one tap away through `PlaceLookup`.
protocol PlaceDiscoveryProvider: Sendable {
    /// Places of a kind, within a radius, ordered nearest first.
    ///
    /// Returning an empty array is a normal answer — "nothing within five miles" is information.
    /// Only a genuine failure throws.
    func places(
        near coordinate: CLLocationCoordinate2D,
        radiusMiles: Double,
        kind: PlaceKind,
        matching term: String?
    ) async throws -> [DiscoveredPlace]
}

/// Somewhere that came back from a search.
struct DiscoveredPlace: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// "Restaurant", "Hotel" — what Apple calls it, tidied for reading.
    let category: String?
    let address: String?
    let latitude: Double
    let longitude: Double
    /// Nearest first is only meaningful if this is known; it always is for a nearby search.
    let distanceMiles: Double?
    let phone: String?
    let website: URL?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The number, dialable.
    ///
    /// MapKit returns it formatted for reading — "(718) 555-0148" — and `tel:` will not take the
    /// brackets and spaces. Lives here rather than in the view so it can be tested; a tap that
    /// silently does nothing is exactly the kind of thing that ships unnoticed.
    var telephoneURL: URL? {
        guard let phone else { return nil }
        let dialable = phone.filter { $0.isNumber || $0 == "+" }
        guard !dialable.isEmpty else { return nil }
        return URL(string: "tel:\(dialable)")
    }

    /// How it reads on a chip: "Lucia's · 0.4 mi".
    var subtitle: String {
        let distance = distanceMiles.map { String(format: "%.1f mi", $0) }
        return [category, distance].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - What each kind means to MapKit

extension PlaceKind {
    /// The point-of-interest categories Apple searches for this kind.
    ///
    /// Grouped rather than one-to-one because the words people use are broader than Apple's
    /// taxonomy: somebody looking for dinner will accept a café or a bakery, and "a drink" covers
    /// a brewery, a winery and a nightclub. Searching one category each would make the list look
    /// broken in a town without a literal `.restaurant`.
    var pointOfInterestCategories: [MKPointOfInterestCategory] {
        switch self {
        case .restaurant: return [.restaurant, .cafe, .bakery]
        case .bar: return [.brewery, .nightlife, .winery]
        case .stay: return [.hotel]
        // Not "what is on" — MapKit does not know that. These are the *places* live events happen,
        // which is the most an on-device search can honestly offer. Ticketmaster answers the rest.
        //
        // `.musicVenue` arrived in iOS 18 and the deployment target is 17, so it is added rather
        // than assumed: on 17 the list is still useful, just broader.
        case .event:
            var categories: [MKPointOfInterestCategory] = [.theater, .stadium, .amusementPark]
            if #available(iOS 18.0, *) { categories.insert(.musicVenue, at: 0) }
            return categories
        }
    }

    /// What to type into a search when a category filter is not enough on its own.
    var searchTerm: String {
        switch self {
        case .restaurant: return "restaurant"
        case .bar: return "bar"
        case .stay: return "hotel"
        case .event: return "live music"
        }
    }

    var displayName: String {
        switch self {
        case .restaurant: return "Food"
        case .bar: return "Drinks"
        case .stay: return "Stay"
        case .event: return "Events"
        }
    }

    var symbolName: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .bar: return "wineglass"
        case .stay: return "bed.double"
        case .event: return "music.mic"
        }
    }
}

// MARK: - MapKit

/// `MKLocalSearch`, which needs no key and no network of ours.
struct MapKitPlaceDiscoveryProvider: PlaceDiscoveryProvider {

    /// The most a person will scroll through on a chip row before it stops being a shortcut.
    static let resultLimit = 15

    func places(
        near coordinate: CLLocationCoordinate2D,
        radiusMiles: Double,
        kind: PlaceKind,
        matching term: String?
    ) async throws -> [DiscoveredPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term?.isEmpty == false ? term : kind.searchTerm
        request.pointOfInterestFilter = MKPointOfInterestFilter(
            including: kind.pointOfInterestCategories
        )
        request.region = Self.region(around: coordinate, radiusMiles: radiusMiles)
        request.resultTypes = .pointOfInterest

        let response = try await MKLocalSearch(request: request).start()
        return Self.places(from: response.mapItems, origin: coordinate, radiusMiles: radiusMiles)
    }

    /// A square region whose half-width is the radius, because `MKCoordinateRegion` has no notion
    /// of a circle. Results are filtered to the true radius afterwards, or a 5-mile search would
    /// return somewhere 7 miles away diagonally.
    static func region(
        around coordinate: CLLocationCoordinate2D,
        radiusMiles: Double
    ) -> MKCoordinateRegion {
        let metres = max(500, radiusMiles * 1609.344) * 2
        return MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: metres,
            longitudinalMeters: metres
        )
    }

    /// Turns Apple's results into ours: measured, filtered to the radius, nearest first, capped.
    ///
    /// Pure and static so it can be tested without a network — `MKMapItem` is constructible, which
    /// is the whole reason the mapping lives here rather than inline in `places(near:)`.
    static func places(
        from items: [MKMapItem],
        origin: CLLocationCoordinate2D,
        radiusMiles: Double
    ) -> [DiscoveredPlace] {
        let from = CLLocation(latitude: origin.latitude, longitude: origin.longitude)

        return items.compactMap { item -> DiscoveredPlace? in
            let placemark = item.placemark
            guard let name = item.name, !name.isEmpty else { return nil }
            let there = CLLocation(
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude
            )
            let miles = from.distance(from: there) / 1609.344
            // Beyond what was asked for. The region is a square and the radius is a circle.
            guard miles <= radiusMiles else { return nil }

            return DiscoveredPlace(
                id: "\(name)|\(placemark.coordinate.latitude),\(placemark.coordinate.longitude)",
                name: name,
                category: item.pointOfInterestCategory.map(Self.readableCategory),
                address: Self.address(from: placemark),
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude,
                distanceMiles: (miles * 10).rounded() / 10,
                phone: item.phoneNumber,
                website: item.url
            )
        }
        .sorted { ($0.distanceMiles ?? .infinity) < ($1.distanceMiles ?? .infinity) }
        .prefix(resultLimit)
        .reduce(into: [DiscoveredPlace]()) { $0.append($1) }
    }

    /// `MKPOICategory(rawValue: "MKPOICategoryRestaurant")` is not a word anyone should read.
    static func readableCategory(_ category: MKPointOfInterestCategory) -> String {
        let raw = category.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
        // Split a camel-cased identifier into words: "MovieTheater" → "Movie Theater".
        var words = ""
        for character in raw {
            if character.isUppercase && !words.isEmpty { words.append(" ") }
            words.append(character)
        }
        return words
    }

    /// Street and city only. A full postal address on a chip is noise.
    static func address(from placemark: MKPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let parts = [street.isEmpty ? nil : street, placemark.locality].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - Looking a place up elsewhere

/// Where to send somebody for the ratings and photos MapKit does not carry.
///
/// The trade made when places moved on-device: Apple gives a name, an address and a category, and
/// nothing about whether the food is any good. Rather than pay for that, it is one tap away — and
/// a link needs no key, no partnership and no disclosure.
enum PlaceLookup: String, CaseIterable, Identifiable, Sendable {
    case appleMaps
    case googleMaps
    case yelp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMaps: return "Maps"
        case .googleMaps: return "Google"
        case .yelp: return "Yelp"
        }
    }

    /// A search rather than a place ID, because an ID from one service means nothing to another.
    /// The name and coordinate are what every one of them accepts.
    func url(for place: DiscoveredPlace) -> URL? {
        let name = place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let coordinate = "\(place.latitude),\(place.longitude)"
        switch self {
        case .appleMaps:
            return URL(string: "https://maps.apple.com/?q=\(name)&ll=\(coordinate)")
        case .googleMaps:
            return URL(string: "https://www.google.com/maps/search/?api=1&query=\(name)&query_place_id=")
                .flatMap { _ in
                    URL(string: "https://www.google.com/maps/search/\(name)/@\(coordinate),16z")
                }
        case .yelp:
            return URL(string: "https://www.yelp.com/search?find_desc=\(name)&find_loc=\(coordinate)")
        }
    }
}

/// Fixed nearby places for previews, screenshots and UI tests.
///
/// Real ones would make every screenshot depend on where the machine running it happens to be,
/// and `MKLocalSearch` needs a network that a test should not.
struct MockPlaceDiscoveryProvider: PlaceDiscoveryProvider {
    private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    func places(
        near coordinate: CLLocationCoordinate2D,
        radiusMiles: Double,
        kind: PlaceKind,
        matching term: String?
    ) async throws -> [DiscoveredPlace] {
        // A beat, so the loading state is a real state rather than a frame nobody sees.
        try? await Task.sleep(for: .milliseconds(400))

        struct Seed {
            let name: String
            let category: String
            let miles: Double
            /// Its own address, number and site — not a shared default.
            ///
            /// These began as one placeholder repeated across every fixture, so the detail sheet
            /// said "1 Example Street" and "(718) 555-0148" whichever place you opened. The screen
            /// looked like it was ignoring which place you tapped, which is exactly what a bug
            /// here would look like.
            let address: String
            let phone: String
            let site: String
            /// Which way from here, in degrees. With the distance above it fixes an actual spot.
            ///
            /// Places used to be offset by their index *within their own kind*, so the first place
            /// of every category landed on precisely the same coordinate — and Look Around, asked
            /// four times about one point, returned one photograph. Two different venues showed
            /// the same street. The bearings also keep to Manhattan, where there is coverage:
            /// due west of midtown is the Hudson.
            let bearing: Double
        }
        let seeds: [Seed]
        switch kind {
        case .restaurant:
            seeds = [
                Seed(
                    name: "Lucia's",
                    category: "Restaurant",
                    miles: 0.4,
                    address: "214 Smith Street, Brooklyn",
                    phone: "(718) 555-0148",
                    site: "luciasbrooklyn.example",
                    bearing: 350
                ),
                Seed(
                    name: "Copper & Oak",
                    category: "Restaurant",
                    miles: 0.9,
                    address: "77 Atlantic Avenue, Brooklyn",
                    phone: "(718) 555-0231",
                    site: "copperandoak.example",
                    bearing: 175
                ),
                Seed(
                    name: "The Daily Grind",
                    category: "Cafe",
                    miles: 1.2,
                    address: "6 Bergen Street, Brooklyn",
                    phone: "(718) 555-0396",
                    site: "dailygrind.example",
                    bearing: 10
                ),
                Seed(
                    name: "Fen Bakery",
                    category: "Bakery",
                    miles: 2.1,
                    address: "158 Court Street, Brooklyn",
                    phone: "(718) 555-0574",
                    site: "fenbakery.example",
                    bearing: 185
                )
            ]
        case .bar:
            seeds = [
                Seed(
                    name: "The Bell Jar",
                    category: "Nightlife",
                    miles: 0.6,
                    address: "42 Wythe Avenue, Brooklyn",
                    phone: "(718) 555-0612",
                    site: "thebelljar.example",
                    bearing: 95
                ),
                Seed(
                    name: "Foxglove Brewing",
                    category: "Brewery",
                    miles: 1.8,
                    address: "301 Nostrand Avenue, Brooklyn",
                    phone: "(718) 555-0789",
                    site: "foxglovebrewing.example",
                    bearing: 355
                )
            ]
        case .stay:
            seeds = [
                Seed(
                    name: "The Rowan Hotel",
                    category: "Hotel",
                    miles: 1.1,
                    address: "88 Dean Street, Brooklyn",
                    phone: "(718) 555-0925",
                    site: "rowanhotel.example",
                    bearing: 170
                ),
                Seed(
                    name: "Harbour Inn",
                    category: "Hotel",
                    miles: 3.4,
                    address: "5 Pier Lane, Brooklyn",
                    phone: "(718) 555-1043",
                    site: "harbourinn.example",
                    bearing: 180
                )
            ]
        case .event:
            seeds = [
                Seed(
                    name: "The Bell House",
                    category: "Music Venue",
                    miles: 0.8,
                    address: "149 7th Street, Brooklyn",
                    phone: "(718) 555-1177",
                    site: "thebellhouse.example",
                    bearing: 200
                ),
                Seed(
                    name: "Regent Theatre",
                    category: "Theater",
                    miles: 2.6,
                    address: "23 Flatbush Avenue, Brooklyn",
                    phone: "(718) 555-1288",
                    site: "regenttheatre.example",
                    bearing: 5
                )
            ]
        }

        return seeds
            .filter { $0.miles <= radiusMiles }
            .enumerated()
            .map { index, seed in
                DiscoveredPlace(
                    id: "mock-\(kind.rawValue)-\(index)",
                    name: seed.name,
                    category: seed.category,
                    address: seed.address,
                    latitude: coordinate.latitude + (seed.miles / 69.0) * cos(radians(seed.bearing)),
                    longitude: coordinate.longitude
                        + (seed.miles / (69.0 * cos(radians(coordinate.latitude))))
                        * sin(radians(seed.bearing)),
                    distanceMiles: seed.miles,
                    phone: seed.phone,
                    website: URL(string: "https://\(seed.site)")
                )
            }
    }
}
