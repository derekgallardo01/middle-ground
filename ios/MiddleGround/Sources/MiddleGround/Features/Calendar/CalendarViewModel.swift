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

    var currentMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
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

    func changeMonth(by value: Int) {
        selectedDate = Calendar.current.date(byAdding: .month, value: value, to: selectedDate) ?? selectedDate
    }
}
