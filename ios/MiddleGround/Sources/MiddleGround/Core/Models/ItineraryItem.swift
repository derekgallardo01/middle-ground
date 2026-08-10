import Foundation

/// One thing on a trip: a dinner, a train, a museum, "check in".
///
/// A trip is currently one title, one place and a range of dates — enough to agree on going, and
/// nothing at all for the part where four people need to know that Thursday's train is at 07:40.
/// That conversation happens today in the negotiation chain, which is a poor place for it: the
/// chain is a transcript, it lives on the request document that is already flagged as a 1 MB
/// hazard, and nothing in it can be sorted, checked off or read as a plan for Thursday.
///
/// **A subcollection, not a field.** `requests/{id}/itinerary/{itemID}`, for the reason `messages`
/// is one: a five-day trip with four people adding items is precisely the shape that pushes a
/// document towards its ceiling, and every read of the plan would carry the whole itinerary
/// whether or not anybody opened it.
struct ItineraryItem: Identifiable, Hashable, Codable, Sendable {

    let id: String
    /// Who added it. Items are editable by their author, the same rule messages follow.
    let authorID: String
    var title: String
    /// When it happens. Optional on purpose: "somewhere for lunch on the 14th" is a real item and
    /// a real thing to agree on, and forcing a time on it invents a precision nobody has.
    var at: Date?
    var location: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        authorID: String,
        title: String,
        at: Date? = nil,
        location: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.authorID = authorID
        self.title = ItineraryItem.clamp(title)
        self.at = at
        self.location = location.map { ItineraryItem.clamp($0, to: RequestLimits.location) }
        self.createdAt = createdAt
    }

    /// Tolerates items written before a field existed, the same way `Request` does.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        authorID = try container.decode(String.self, forKey: .authorID)
        title = try container.decode(String.self, forKey: .title)
        at = try container.decodeIfPresent(Date.self, forKey: .at)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    static func clamp(_ text: String, to limit: Int = RequestLimits.title) -> String {
        RequestLimits.clamp(text.trimmingCharacters(in: .whitespacesAndNewlines), to: limit)
    }

    var isScheduled: Bool { at != nil }
}

/// A day of a trip, with what is on it.
///
/// Days are derived rather than stored, so an item cannot end up filed under a day the trip does
/// not have — which is what happens the first time somebody moves the dates.
struct ItineraryDay: Identifiable, Hashable, Sendable {
    /// Midnight at the start of the day, **in the plan's zone**.
    let date: Date
    /// The day's number, counting the first day of the trip as 1.
    let number: Int
    let items: [ItineraryItem]

    var id: Date { date }
}

extension Request {

    /// Groups items into the days of this trip.
    ///
    /// Computed in the plan's own zone (`Request+TimeZone`), which is the whole reason that field
    /// exists: dinner at 20:00 in Barcelona is on the 14th there and, to somebody reading from
    /// Chicago, at 13:00 on a day the app would otherwise file it under. An itinerary that sorts
    /// itself by the reader's calendar is worse than no itinerary, because it looks right.
    ///
    /// Every day of the trip appears, including the empty ones — a gap is information ("nothing on
    /// Wednesday yet"), and a list that silently skips days cannot be read as an itinerary.
    func itineraryDays(from items: [ItineraryItem]) -> [ItineraryDay] {
        guard let start = proposedTime, let finish = effectiveEndTime else { return [] }
        var calendar = Calendar.current
        calendar.timeZone = displayTimeZone

        let firstDay = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: finish)
        let span = calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0

        let scheduled = items.filter(\.isScheduled).sorted {
            ($0.at ?? .distantPast, $0.createdAt) < ($1.at ?? .distantPast, $1.createdAt)
        }

        return (0...max(0, span)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return nil
            }
            let onThisDay = scheduled.filter {
                guard let at = $0.at else { return false }
                return calendar.isDate(at, inSameDayAs: day)
            }
            return ItineraryDay(date: day, number: offset + 1, items: onThisDay)
        }
    }

    /// Items with no time yet — real plans that nobody has pinned down.
    ///
    /// Kept separate rather than dropped into the first day, which is where they would otherwise
    /// land and be quietly wrong.
    func unscheduledItinerary(from items: [ItineraryItem]) -> [ItineraryItem] {
        items.filter { !$0.isScheduled }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Items that fall outside the trip entirely — the ones a date change stranded.
    ///
    /// Shown rather than hidden. When somebody moves a trip a week later, everything already
    /// arranged is suddenly outside it; silently dropping those items loses work people did, and
    /// silently keeping them in day one puts a museum booking on the wrong morning.
    func strandedItinerary(from items: [ItineraryItem]) -> [ItineraryItem] {
        guard proposedTime != nil, effectiveEndTime != nil else { return [] }
        return items
            .filter { item in
                guard let at = item.at else { return false }
                return !covers(at)
            }
            .sorted { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }
    }
}
