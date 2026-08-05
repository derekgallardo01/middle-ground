import Foundation

/// Who in a group has blocked out a given day, and who simply has not said.
///
/// The app has stored this since shared availability shipped and never surfaced it at the moment
/// it matters: a time was chosen blind, and the only warning was about the chooser's own calendar.
/// Somebody else having marked that Saturday as impossible was visible on the Calendar tab and
/// nowhere near the picker.
///
/// **Absence is not availability, and that is the whole reason this is a type.** Somebody who has
/// never opened the Calendar tab has no document at all. Counting them as free is the same mistake
/// `CalendarAvailability.unknown` exists to prevent — an app that says "everyone is free" when it
/// simply has not been told is worse than one that says nothing. So the answer is three-valued:
/// names known to be busy, and a count of people who have said nothing either way.
///
/// A pure factory in the shape of `GroupScoreboard.from` and `ReliabilityScore.from` — filtering
/// inside, so no call site can forget a rule.
struct GroupBusyDay: Equatable, Sendable {
    /// People in the group who blocked this day out, by display name, sorted.
    let busyNames: [String]
    /// People who have never shared any availability, so nothing is known about them.
    let silentCount: Int

    var somebodyIsBusy: Bool { !busyNames.isEmpty }

    /// The sentence to put under a date picker, or nil when there is nothing worth saying.
    ///
    /// Silence alone is not worth a line. "Two people haven't said" next to every date would be
    /// noise on the overwhelming majority of days, and would train people to ignore the row that
    /// matters.
    var warning: String? {
        guard somebodyIsBusy else { return nil }
        let who = busyNames.count == 1
            ? "\(busyNames[0]) isn't free then"
            : "\(busyNames.formatted(.list(type: .and))) aren't free then"
        return silentCount > 0 ? "\(who). \(silentCount) more haven't said." : who
    }

    /// Builds the answer for one day from what the group has shared.
    ///
    /// - Parameters:
    ///   - availability: every `SharedAvailability` known for the group, the viewer's included.
    ///   - members: everybody in the group, so silence can be counted rather than assumed.
    ///   - viewerID: excluded — your own blocked days are not news to you.
    ///   - names: display names by user ID; anybody missing is skipped rather than called
    ///     "Someone", because a warning that cannot say who is not actionable.
    static func on(
        _ day: Date,
        availability: [SharedAvailability],
        members: [String],
        viewerID: String,
        names: [String: String],
        calendar: Calendar = .current
    ) -> GroupBusyDay {
        let others = members.filter { $0 != viewerID }
        let byUser = Dictionary(uniqueKeysWithValues: availability.map { ($0.userID, $0) })

        var busy: [String] = []
        var silent = 0

        for member in others {
            guard let shared = byUser[member] else {
                silent += 1          // never opened the calendar; nothing is known
                continue
            }
            if shared.isBusy(on: day, calendar: calendar), let name = names[member] {
                busy.append(name)
            }
        }

        return GroupBusyDay(busyNames: busy.sorted(), silentCount: silent)
    }
}
