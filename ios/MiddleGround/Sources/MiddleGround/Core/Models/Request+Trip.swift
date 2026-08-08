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
}
