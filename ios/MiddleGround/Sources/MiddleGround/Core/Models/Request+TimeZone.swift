import Foundation

/// What time a plan happens **where it happens**.
///
/// Every date in this app renders in the reader's zone, and that is right almost always — a dinner
/// across town is at 8 for everybody who might go. It stops being right the moment the plan is
/// somewhere else: "dinner at 8" in Barcelona reads as 8pm to somebody sitting in Chicago, which is
/// seven hours from when anybody is actually eating. The trip is the whole reason this exists;
/// domestic plans keep the old behaviour untouched because `timeZoneID` is nil on them.
///
/// The comparison here is **offset at that instant**, never identifier equality. Two zones with
/// different names can be the same clock — Europe/Dublin and Europe/London, America/New_York and
/// America/Detroit — and telling somebody in London that a plan is in "Irish Standard Time" is
/// noise about a difference that does not exist. It is measured at the plan's own instant rather
/// than now, because a trip in October may cross a daylight-saving boundary that today is on the
/// other side of.
extension Request {

    /// The zone the plan is in, when it was recorded and is a zone this device knows.
    ///
    /// An unrecognised identifier resolves to nil and everything falls back to the reader's clock,
    /// which is the behaviour every plan had before this shipped.
    var timeZone: TimeZone? {
        timeZoneID.flatMap(TimeZone.init(identifier:))
    }

    /// Whether the plan's clock and the reader's actually differ, at the plan's own instant.
    var isInAnotherTimeZone: Bool {
        guard let timeZone, let proposedTime else { return false }
        return timeZone.secondsFromGMT(for: proposedTime)
            != TimeZone.current.secondsFromGMT(for: proposedTime)
    }

    /// The zone to render in: the plan's when it differs, otherwise the reader's.
    var displayTimeZone: TimeZone {
        isInAnotherTimeZone ? (timeZone ?? .current) : .current
    }

    /// How to name the plan's clock, once — "Central European Time".
    ///
    /// The localised generic name rather than the identifier's city, because the city in an
    /// identifier is frequently not where the plan is: a trip to Barcelona is `Europe/Madrid`, and
    /// "Madrid time" would be a confident wrong answer about a place nobody is going. Falls back to
    /// the city only when the system has no name to give.
    var timeZoneName: String? {
        guard isInAnotherTimeZone, let timeZone else { return nil }
        if let name = timeZone.localizedName(for: .generic, locale: .current), !name.isEmpty {
            return name
        }
        return timeZone.identifier.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") }
    }

    /// The hour the plan starts, on the clock of the place it is in.
    ///
    /// Nil when there is no time, and nil when the plan is on the reader's own clock — there is
    /// nothing to disambiguate then, and a redundant "7:30 PM Eastern Time" under a date is worse
    /// than saying nothing.
    var localTimeSummary: String? {
        guard isInAnotherTimeZone, let proposedTime, let name = timeZoneName else { return nil }
        let hour = proposedTime.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, timeZone: displayTimeZone)
        )
        return "\(hour) \(name)"
    }
}
