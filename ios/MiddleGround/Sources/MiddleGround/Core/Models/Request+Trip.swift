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
    var dateSummary: String? {
        guard let proposedTime else { return nil }
        guard isMultiDay, let endTime else {
            return proposedTime.formatted(date: .abbreviated, time: .omitted)
        }
        // The year is asked for, because the single-date branch above includes one — a list mixing
        // "Jan 15 – 19" with "Jan 15, 2027" reads like two different apps. `isMultiDay` guarantees
        // the end is after the start, so this range can never be malformed.
        return (proposedTime..<endTime).formatted(.interval.day().month(.abbreviated).year())
    }

    /// "5 nights" — how long a trip runs, for the places a range is too long to print.
    var nightCount: Int? {
        guard isMultiDay, let proposedTime, let endTime else { return nil }
        return Calendar.current.dateComponents([.day], from: proposedTime, to: endTime).day
    }
}
