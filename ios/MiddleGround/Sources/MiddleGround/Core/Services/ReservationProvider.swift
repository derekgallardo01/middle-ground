import Foundation

/// The seam a booking partner drops into.
///
/// Built before there is a partner on purpose. Booking access is granted on terms and timelines
/// nobody here controls, and the shape of the work is the same whether the answer is OpenTable,
/// Resy, Tock or nothing: find a place, hand someone a link, and — if a partner ever says yes —
/// hold a reservation and follow what happens to it. Writing that interface now means approval
/// changes one registration in `Dependencies` instead of reaching into the compose screen, and a
/// refusal costs nothing because the link-only provider is genuinely useful on its own.
///
/// The protocol deliberately does **not** assume booking exists. A provider declares what it can
/// do through `capabilities`, and callers ask before offering it — otherwise every screen ends up
/// with a Book button that throws for the only provider actually shipping.
protocol ReservationProvider: Sendable {
    /// Stable identifier stored on any reservation this provider creates, so a row written by one
    /// provider is never handed to another for cancellation.
    var id: String { get }
    var displayName: String { get }
    var capabilities: Set<ReservationCapability> { get }

    /// Places matching a plan's location and party size. May be the curated list, a Places API,
    /// or a partner's own inventory.
    func search(near location: String?, partySize: Int, at time: Date?) async throws -> [ReservableVenue]

    /// Where to send someone to book this themselves. Always available — this is the fallback
    /// that makes the feature useful without any partnership at all.
    func bookingURL(for venue: ReservableVenue, partySize: Int, at time: Date?) -> URL?

    /// Holds a table. Throws `.notSupported` unless `capabilities` contains `.booking`.
    func book(_ venue: ReservableVenue, partySize: Int, at time: Date) async throws -> Reservation

    func cancel(_ reservation: Reservation) async throws

    func status(of reservation: Reservation) async throws -> ReservationStatus
}

enum ReservationCapability: String, Sendable {
    /// Can find places. Every provider does at least this.
    case search
    /// Can produce a link that books elsewhere.
    case link
    /// Can hold a table without leaving the app. Requires a partnership.
    case booking
}

enum ReservationError: Error, Equatable {
    /// The provider cannot do this, and the caller should have checked `capabilities` first.
    case notSupported
    case noAvailability
    case providerUnavailable
}

/// A place that could be booked, whatever the source.
///
/// `providerVenueID` is opaque on purpose: a curated Firestore ID, a Google Places ID and a
/// partner's restaurant ID are all just strings to everything above this layer.
struct ReservableVenue: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let city: String
    let address: String?
    /// Which provider this came from, and the ID that provider knows it by.
    let providerID: String
    let providerVenueID: String

    init(
        id: String = UUID().uuidString,
        name: String,
        city: String,
        address: String? = nil,
        providerID: String,
        providerVenueID: String
    ) {
        self.id = id
        self.name = name
        self.city = city
        self.address = address
        self.providerID = providerID
        self.providerVenueID = providerVenueID
    }
}

struct Reservation: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let providerID: String
    let venueName: String
    let partySize: Int
    let at: Date
    var status: ReservationStatus
}

enum ReservationStatus: String, Codable, Sendable {
    case pending
    case confirmed
    case cancelled
    /// The provider was asked and could not say. Distinct from `pending`, which means it told us.
    case unknown
}

// MARK: - v1

/// What ships today: the curated venue list, plus a link that opens OpenTable's public search.
///
/// No partnership, no API key, no billing. It cannot hold a table — `capabilities` says so, and
/// `book` refuses rather than pretending. When a partner does say yes, that implementation
/// replaces this one behind the same protocol; until then this is the whole feature, and it is
/// the same one people already do by hand after agreeing on a place.
struct CuratedVenueReservationProvider: ReservationProvider {
    let id = "curated"
    let displayName = "Suggested places"
    let capabilities: Set<ReservationCapability> = [.search, .link]

    private let venues: VenueRepository

    init(venues: VenueRepository) {
        self.venues = venues
    }

    func search(near location: String?, partySize: Int, at time: Date?) async throws -> [ReservableVenue] {
        let all = try await venues.venues()
        // The curated list is small and city-scoped; matching on city is what makes "near" mean
        // anything at all without a geocoder.
        let matched = all.filter { venue in
            guard let location, !location.isEmpty else { return true }
            return venue.city.localizedCaseInsensitiveContains(location)
                || location.localizedCaseInsensitiveContains(venue.city)
                || venue.name.localizedCaseInsensitiveContains(location)
        }
        return (matched.isEmpty ? all : matched).map {
            ReservableVenue(
                name: $0.name,
                city: $0.city,
                address: $0.address,
                providerID: id,
                providerVenueID: $0.id
            )
        }
    }

    /// OpenTable's public search URL — a web link anyone can construct, not an API. It carries the
    /// party size and time we already know, so the person lands on availability rather than on a
    /// form they have to fill in again.
    func bookingURL(for venue: ReservableVenue, partySize: Int, at time: Date?) -> URL? {
        var components = URLComponents(string: "https://www.opentable.com/s")
        var items = [
            URLQueryItem(name: "term", value: venue.name),
            URLQueryItem(name: "covers", value: String(partySize))
        ]
        if let time {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
            items.append(URLQueryItem(name: "dateTime", value: formatter.string(from: time)))
        }
        components?.queryItems = items
        return components?.url
    }

    func book(_ venue: ReservableVenue, partySize: Int, at time: Date) async throws -> Reservation {
        throw ReservationError.notSupported
    }

    func cancel(_ reservation: Reservation) async throws {
        throw ReservationError.notSupported
    }

    func status(of reservation: Reservation) async throws -> ReservationStatus {
        throw ReservationError.notSupported
    }
}
