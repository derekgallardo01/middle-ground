import Factory
import Foundation

/// Watches one proposed time and says whether the device calendar already has something then.
///
/// Extracted because the check existed only on the create screen. Suggesting a new time and
/// countering with one — the two places where a time is chosen *knowing* the other person is
/// waiting — had no clash check at all, so the app would warn you about double-booking yourself
/// when proposing a plan and stay silent when rescheduling it.
///
/// Three rules are carried from the original and are the whole reason this is a type:
///
/// 1. **Scrubbing is coalesced.** A date picker emits continuously while a finger moves; without
///    the delay this would ask EventKit a hundred times for one decision.
/// 2. **`.unknown` is not `.free`.** When access has not been granted the answer is "could not
///    look", and the UI says nothing. Implying a slot is clear when the app never checked is the
///    failure worth designing against.
/// 3. **Permission is never requested implicitly.** `hasAccess` only reports; asking is an
///    explicit call, made when somebody taps the row.
@MainActor
@Observable
final class CalendarClashChecker {
    private let calendarService = Container.shared.calendarConflictService()

    private(set) var availability: CalendarAvailability = .unknown

    var accessGranted: Bool { calendarService.hasAccess }

    private var inFlight: Task<Void, Never>?

    /// Checks `time`, or clears the answer when there is nothing to check.
    ///
    /// Pass nil when the time has been switched off — leaving the previous verdict on screen
    /// would attach a warning to a plan that no longer carries a time.
    func check(_ time: Date?) {
        inFlight?.cancel()
        guard let time, calendarService.hasAccess else {
            availability = .unknown
            return
        }
        inFlight = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            let result = await calendarService.availability(
                at: time,
                duration: CalendarConflictService.assumedDuration
            )
            guard !Task.isCancelled else { return }
            self.availability = result
        }
    }

    /// Asks for calendar access, then answers the question that prompted it.
    func requestAccess(then time: Date?) async {
        await calendarService.requestAccess()
        check(time)
    }
}
