import Foundation

/// Where to send somebody to finish a booking, when nobody will grant an API.
///
/// OpenTable declined. Resy has been partner-only since American Express bought it, Airbnb closed
/// its public API to new developers, and Kayak's is partner-gated. That sounds like four closed
/// doors and is really only one: **a public search URL needs nobody's permission**, and finishing
/// a booking on the service's own site is what people do anyway.
///
/// So this is deliberately not an integration. It is a well-addressed link — carrying the place,
/// the party size, the dates — so that nobody retypes what the plan already knows. The app never
/// claims to have booked anything; `ReservationProvider.capabilities` is what draws that line, and
/// it still reports `.link` rather than `.booking`.
///
/// Pure functions on purpose: no network, no keys, no dependencies, so they are trivially testable
/// and cannot fail at runtime in a way a person would have to understand.
enum BookingDestination: String, CaseIterable, Identifiable, Sendable {
    case openTable
    case resy
    case kayak
    case airbnb

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openTable: return "OpenTable"
        case .resy: return "Resy"
        case .kayak: return "Kayak"
        case .airbnb: return "Airbnb"
        }
    }

    /// SF Symbol for the button. Restaurants get cutlery, stays get a bed.
    var symbolName: String {
        switch self {
        case .openTable, .resy: return "fork.knife"
        case .kayak, .airbnb: return "bed.double"
        }
    }

    /// Which destinations make sense for a kind of place.
    ///
    /// A restaurant on Airbnb is nonsense, and offering every service for everything is how a row
    /// of buttons becomes a row of shrugs.
    static func options(for kind: PlaceKind) -> [BookingDestination] {
        switch kind {
        case .restaurant, .bar: return [.openTable, .resy]
        case .stay: return [.kayak, .airbnb]
        case .event: return []
        }
    }
}

/// What sort of place a plan is about, which decides where a booking link should point.
enum PlaceKind: String, CaseIterable, Sendable {
    case restaurant
    case bar
    case stay
    case event
}

/// Builds the search URLs.
///
/// Each is the service's own public search, with the plan's details filled in. They are documented
/// individually because they are the part most likely to rot: a query parameter renamed upstream
/// produces a page that loads and ignores everything we told it, which is worse than a 404 because
/// nothing looks wrong.
enum BookingLinkBuilder {

    /// `dateTime` in the local ISO form OpenTable's search expects, which is not `.iso8601` —
    /// that appends a zone and the search then ignores it.
    static func openTable(place: String, partySize: Int, at time: Date?) -> URL? {
        var components = URLComponents(string: "https://www.opentable.com/s")
        var items = [
            URLQueryItem(name: "term", value: place),
            URLQueryItem(name: "covers", value: String(max(1, partySize)))
        ]
        if let time {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
            // Local wall-clock time, not UTC. `ISO8601DateFormatter` defaults to GMT, and the
            // parameter carries no zone — so a 7:30pm dinner was arriving at OpenTable as 23:30
            // for anyone east or west of London, and the page loaded perfectly showing the wrong
            // evening. The link has to say the hour the app is showing.
            formatter.timeZone = .current
            items.append(URLQueryItem(name: "dateTime", value: formatter.string(from: time)))
        }
        components?.queryItems = items
        return components?.url
    }

    /// Resy's public search. It takes a free-text query and a party size; it does **not** accept a
    /// time in the URL, so the time is deliberately left off rather than passed and dropped.
    static func resy(place: String, partySize: Int, at time: Date?) -> URL? {
        var components = URLComponents(string: "https://resy.com/search")
        var items = [URLQueryItem(name: "query", value: place)]
        if partySize > 0 {
            items.append(URLQueryItem(name: "seats", value: String(partySize)))
        }
        if let time {
            // Date only. Resy reads the day; the hour is chosen on their page.
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            items.append(URLQueryItem(name: "date", value: formatter.string(from: time)))
        }
        components?.queryItems = items
        return components?.url
    }

    /// Kayak hotel search: `/hotels/{place}/{checkIn}/{checkOut}/{guests}adults`.
    ///
    /// Path segments rather than query parameters, which is why the place is slugified — a comma
    /// or a space in a path segment produces a URL Kayak answers with its home page.
    static func kayak(place: String, checkIn: Date, checkOut: Date, guests: Int) -> URL? {
        let slug = slugify(place)
        guard !slug.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let path = "https://www.kayak.com/hotels/\(slug)/"
            + "\(formatter.string(from: checkIn))/\(formatter.string(from: checkOut))/"
            + "\(max(1, guests))adults"
        return URL(string: path)
    }

    /// Airbnb search: `/s/{place}/homes` with the dates and party size as query parameters.
    static func airbnb(place: String, checkIn: Date, checkOut: Date, guests: Int) -> URL? {
        let slug = slugify(place)
        guard !slug.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents(string: "https://www.airbnb.com/s/\(slug)/homes")
        components?.queryItems = [
            URLQueryItem(name: "checkin", value: formatter.string(from: checkIn)),
            URLQueryItem(name: "checkout", value: formatter.string(from: checkOut)),
            URLQueryItem(name: "adults", value: String(max(1, guests)))
        ]
        return components?.url
    }

    /// Lowercased, punctuation dropped, spaces to hyphens — what both Kayak and Airbnb expect in a
    /// path segment. Diacritics are folded rather than percent-encoded, because "Málaga" as
    /// `M%C3%A1laga` in a path segment resolves to nothing on either site.
    static func slugify(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let allowed = folded.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(allowed)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }
}
