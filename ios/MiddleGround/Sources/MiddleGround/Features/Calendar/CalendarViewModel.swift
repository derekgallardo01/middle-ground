import Foundation
import Factory

@MainActor
@Observable
final class CalendarViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()

    var currentUser: User?
    var selectedDate: Date = Date()
    var events: [Request] = []
    var isLoading = false
    var errorMessage: String?

    /// Tracked separately from `selectedDate`.
    ///
    /// Deriving the month from the selection meant tapping a greyed-out leading/trailing day
    /// silently jumped the whole calendar to another month.
    var currentMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()

    /// True when the user has picked a day with something on it, so the list can narrow to it.
    var hasSelectionWithEvents: Bool {
        !events(for: selectedDate).isEmpty
    }

    /// Events for the selected day, or the next five upcoming when that day is empty.
    /// Selecting a day used to only move a highlight — the list ignored it entirely.
    var listedEvents: [Request] {
        let onSelectedDay = events(for: selectedDate)
        guard onSelectedDay.isEmpty else {
            return onSelectedDay.sorted { ($0.proposedTime ?? .distantPast) < ($1.proposedTime ?? .distantPast) }
        }
        return events
            .compactMap { request -> (Request, Date)? in
                guard let date = request.proposedTime else { return nil }
                return (request, date)
            }
            .filter { $0.1 >= Date().startOfDay }
            .sorted { $0.1 < $1.1 }
            .prefix(5)
            .map(\.0)
    }

    func changeMonth(by delta: Int) {
        guard let moved = Calendar.current.date(byAdding: .month, value: delta, to: currentMonth) else { return }
        currentMonth = moved
    }

    /// Selecting a day never changes the visible month.
    func select(_ date: Date) {
        selectedDate = date
    }

    func loadCurrentUser() async {
        currentUser = await authService.currentUser()
    }

    func loadEvents() async {
        guard let currentUser else {
            errorMessage = "Not signed in."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let requests = try await requestService.fetchRequests(for: currentUser.id)
            events = requests.filter { $0.proposedTime != nil || $0.status == .accepted }
        } catch {
            events = []
            errorMessage = "Couldn't load events. Pull to try again."
        }
        isLoading = false
    }

    func events(for date: Date) -> [Request] {
        events.filter { request in
            guard let requestDate = request.proposedTime else { return false }
            return Calendar.current.isDate(requestDate, inSameDayAs: date)
        }
    }

}
