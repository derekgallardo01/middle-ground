import Foundation

/// A plan that spans days rather than a moment.
///
/// `proposedTime` has always been the only time a plan had, which is why a trip could not be
/// expressed at all: "Barcelona, 12–16 May" is a range, not a time.
///
/// Split out of `Request.swift` for the 500-line limit, the same way the nearby search was split
/// out of `CreateRequestViewModel`. Everything here is derived — nothing new is stored beyond the
/// one optional field.
///
/// **Nothing can create a multi-day plan yet, on purpose.** No screen sets an end, so `endTime` is
/// nil on every plan in production. The schedulers still ask about attendance four hours after the
/// *start*, the rules still pin only `proposedTime`, and the location window is still ±hours
/// around a single moment. A trip made today would behave wrongly in all three, so until those
/// move, one cannot be made.
extension Request {

    /// Whether this plan covers more than a moment.
    ///
    /// An end that is not after the start is not a range — it is a typo or a legacy row, and
    /// treating it as a trip would make every duration negative downstream.
    var isMultiDay: Bool {
        guard let proposedTime, let endTime else { return false }
        return endTime > proposedTime
    }

    /// When the plan is actually over: the end for a trip, the start for everything else.
    ///
    /// The single most important line for a trip. Attendance is asked four hours after a plan
    /// *finishes*, and asking on the first morning of a five-day holiday is asking whether
    /// something that is still happening happened.
    var effectiveEndTime: Date? {
        isMultiDay ? endTime : proposedTime
    }

    /// How the dates read on a card: "12–16 May" for a trip, the date alone otherwise.
    ///
    /// A range shown as its start date only is the bug this exists to prevent — a week in
    /// Barcelona and a Tuesday dinner would look identical everywhere a plan is listed, which is
    /// most places somebody sees one.
    ///
    /// `Date.FormatStyle` rather than a hand-rolled string, so it follows the reader's locale:
    /// the same trip reads "12–16 May" in London and "May 12 – 16" in New York.
    ///
    /// Rendered on the plan's clock when it has one (`Request+TimeZone`). A trip that starts at
    /// 00:30 in Madrid is on the 12th there and the 11th to a reader in Chicago, and the date a
    /// card shows has to be the one on the tickets.
    var dateSummary: String? {
        guard let proposedTime else { return nil }
        let zone = displayTimeZone
        guard isMultiDay, let endTime else {
            return proposedTime.formatted(
                Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: zone)
            )
        }
        // The year is asked for, because the single-date branch above includes one — a list mixing
        // "Jan 15 – 19" with "Jan 15, 2027" reads like two different apps. `isMultiDay` guarantees
        // the end is after the start, so this range can never be malformed.
        var style = Date.IntervalFormatStyle().day().month(.abbreviated).year()
        style.timeZone = zone
        return (proposedTime..<endTime).formatted(style)
    }

    /// Whether this plan occupies a given day.
    ///
    /// The calendar asked `isDate(proposedTime, inSameDayAs:)`, which is the right question about a
    /// dinner and the wrong one about a holiday: a four-night trip appeared on its first day and
    /// nowhere else, so days two, three and four read as free on the one screen people check to
    /// find out whether they are free.
    ///
    /// Days are compared on the plan's own calendar, so a trip abroad occupies the days it does
    /// there. Ends are inclusive of the start day and exclusive of nothing — a trip that ends at
    /// 10am on the 16th still occupies the 16th, because somebody is there that morning.
    func covers(_ day: Date, calendar: Calendar = .current) -> Bool {
        guard let proposedTime else { return false }
        var planCalendar = calendar
        planCalendar.timeZone = displayTimeZone

        guard isMultiDay, let endTime else {
            return planCalendar.isDate(proposedTime, inSameDayAs: day)
        }
        let asked = planCalendar.startOfDay(for: day)
        return asked >= planCalendar.startOfDay(for: proposedTime)
            && asked <= planCalendar.startOfDay(for: endTime)
    }

    /// "5 nights" — how long a trip runs, for the places a range is too long to print.
    ///
    /// Counted on the plan's calendar, not the reader's: four nights in Barcelona is four nights
    /// whether you are reading about it from London or from Los Angeles.
    var nightCount: Int? {
        guard isMultiDay, let proposedTime, let endTime else { return nil }
        var calendar = Calendar.current
        calendar.timeZone = displayTimeZone
        // Between the *days*, not the instants. Counting elapsed 24-hour periods loses a night
        // for every trip that behaves like a real one: land at 15:40 on the 4th, fly home at
        // 11:00 on the 8th, and that is three-and-a-bit periods — so a four-night trip reported
        // "3 nights" beside its own "Four nights" description. Nights are what a hotel counts,
        // and a hotel counts dates.
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: proposedTime),
            to: calendar.startOfDay(for: endTime)
        ).day
    }
}
