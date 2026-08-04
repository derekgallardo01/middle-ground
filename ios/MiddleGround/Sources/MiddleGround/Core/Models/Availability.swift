import Foundation

/// A stretch of time somebody has said they are not free.
///
/// Deliberately says *nothing about why*. No title, no location, no event identifier — only a
/// start and an end. That is the whole reason this feature can exist without breaking the promise
/// the Privacy Policy makes about calendars: **nothing here is read from the device calendar**.
/// The calendar keeps doing what it already does, which is warn *you*, privately, on your own
/// phone. What a group sees is only what you deliberately blocked out.
///
/// If this ever starts being populated from calendar events, that sentence in the policy —
/// "your events stay on your device and are never uploaded or shared" — becomes false, and the
/// policy and the App Privacy answers have to change in the same commit.
struct UnavailableBlock: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let start: Date
    let end: Date
    /// A whole day rather than a slice of one, which is how most people think about being away.
    let isAllDay: Bool

    init(
        id: String = UUID().uuidString,
        start: Date,
        end: Date,
        isAllDay: Bool = false
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }

    /// A whole calendar day, from midnight to midnight.
    static func wholeDay(_ day: Date, calendar: Calendar = .current) -> UnavailableBlock {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return UnavailableBlock(start: start, end: end, isAllDay: true)
    }

    func overlaps(_ otherStart: Date, _ otherEnd: Date) -> Bool {
        start < otherEnd && otherStart < end
    }

    /// Whether this block covers any part of `day`.
    func covers(_ day: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return overlaps(dayStart, dayEnd)
    }
}

/// One person's blocked-out time, as shared with one group.
///
/// Stored per group rather than once per person — `relationships/{id}/availability/{uid}` — for
/// two reasons. The security rules can prove membership of a *named* group by reading that one
/// document, which they cannot do for "everybody who shares any group with me". And it means
/// blocking out time for your football team does not announce it to your family.
struct SharedAvailability: Identifiable, Hashable, Codable, Sendable {
    let userID: String
    var blocks: [UnavailableBlock]
    var updatedAt: Date

    var id: String { userID }

    init(userID: String, blocks: [UnavailableBlock] = [], updatedAt: Date = Date()) {
        self.userID = userID
        self.blocks = blocks
        self.updatedAt = updatedAt
    }

    /// Whether this person is unavailable at any point in the given window.
    func isBusy(from start: Date, to end: Date) -> Bool {
        blocks.contains { $0.overlaps(start, end) }
    }

    func isBusy(on day: Date, calendar: Calendar = .current) -> Bool {
        blocks.contains { $0.covers(day, calendar: calendar) }
    }
}
