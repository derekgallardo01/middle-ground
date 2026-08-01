import EventKit
import Foundation

/// Whether a proposed time clashes with something already in the user's calendar.
///
/// Deliberately three-valued. "I could not look" is not the same as "you are free", and
/// collapsing them would be the worst possible failure for this feature: telling someone a slot
/// is clear when the app simply lacks permission is how a plan gets double-booked.
enum CalendarAvailability: Equatable, Sendable {
    case free
    case busy(String?)
    /// Access not granted, not yet asked, or the lookup failed.
    case unknown

    var isBusy: Bool {
        if case .busy = self { return true }
        return false
    }
}

protocol CalendarConflictChecking: Sendable {
    /// True once the user has granted read access. Never prompts.
    var hasAccess: Bool { get }
    /// Prompts if the user has not been asked. Returns whether access ended up granted.
    @discardableResult
    func requestAccess() async -> Bool
    func availability(at start: Date, duration: TimeInterval) async -> CalendarAvailability
}

/// EventKit-backed. Reads only; nothing is written to the calendar and nothing leaves the device.
///
/// Apple's calendar first because it is cheap — a purpose string and an App Privacy answer. A
/// Google calendar subscribed in iOS Settings is visible through EventKit too, so native Google
/// support buys less than it looks like it would.
struct CalendarConflictService: CalendarConflictChecking {
    /// Plans carry a start time but no end, so a window has to be assumed. An hour is long
    /// enough to catch a real clash and short enough not to flag the whole evening.
    static let assumedDuration: TimeInterval = 60 * 60

    private let store = EKEventStore()

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    @discardableResult
    func requestAccess() async -> Bool {
        // `.fullAccess` rather than write-only: reading existing events is the entire feature,
        // and write-only access cannot see them.
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func availability(at start: Date, duration: TimeInterval = assumedDuration) async -> CalendarAvailability {
        guard hasAccess else { return .unknown }

        let predicate = store.predicateForEvents(
            withStart: start,
            end: start.addingTimeInterval(duration),
            calendars: nil
        )
        let clashing = store.events(matching: predicate).filter { event in
            // All-day entries and anything explicitly marked free are not a conflict — a
            // birthday in the calendar does not mean the evening is taken.
            !event.isAllDay && event.availability != .free && event.status != .canceled
        }

        guard let first = clashing.first else { return .free }
        return .busy(first.title)
    }
}

/// Always `.unknown`, so previews and tests never depend on the host's real calendar.
struct MockCalendarConflictService: CalendarConflictChecking {
    var hasAccess: Bool { false }

    @discardableResult
    func requestAccess() async -> Bool { false }

    func availability(at start: Date, duration: TimeInterval) async -> CalendarAvailability {
        .unknown
    }
}
