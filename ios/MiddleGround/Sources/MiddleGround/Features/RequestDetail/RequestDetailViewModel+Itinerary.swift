import Factory
import Foundation

/// What is on which day of a trip.
///
/// A trip is one title, one place and a range of dates — enough to agree on going, and nothing
/// for the part where four people need to know Thursday's train is at 07:40. That conversation
/// happens in the negotiation chain today, which cannot be sorted, cannot be read as a plan for
/// Thursday, and lives on the document already flagged as a 1 MB hazard.
///
/// **Only on a trip.** A dinner does not need an itinerary — it *is* the itinerary — and putting
/// an empty "Day 1" card under every plan in the app would be the kind of feature that makes the
/// screen longer without making anything easier.
extension RequestDetailViewModel {

    var showsItinerary: Bool {
        request.isMultiDay && request.status != .cancelled && request.status != .declined
    }

    /// Every day of the trip, in order, including the empty ones.
    var itineraryDays: [ItineraryDay] {
        request.itineraryDays(from: itineraryItems)
    }

    /// Things nobody has put a time on yet.
    var unscheduledItinerary: [ItineraryItem] {
        request.unscheduledItinerary(from: itineraryItems)
    }

    /// Things that fall outside the trip — what a change of dates left behind.
    ///
    /// Surfaced rather than dropped. Somebody moved the trip and everything already arranged is
    /// suddenly outside it; hiding those loses work people did, and filing them under day one
    /// puts a booking on the wrong morning.
    var strandedItinerary: [ItineraryItem] {
        request.strandedItinerary(from: itineraryItems)
    }

    func loadItinerary() async {
        guard showsItinerary else { return }
        do {
            itineraryItems = try await itineraryRepository.items(forRequest: request.id)
        } catch {
            // Deliberately quiet. The itinerary is one section of a screen whose main job is the
            // plan itself; taking the whole detail view over with an error because a secondary
            // list failed is the mistake `errorMessage` already made once with the feed.
            MGLog.storage.error("Itinerary load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Adds an item. Empty titles are refused here rather than at the server, which would return
    /// a permission error and read as "you are not allowed" for what is really an empty field.
    func addItineraryItem(title: String, at when: Date?, location: String?) async {
        guard let currentUserID else { return }
        let cleaned = ItineraryItem.clamp(title)
        guard !cleaned.isEmpty else { return }

        let item = ItineraryItem(
            authorID: currentUserID,
            title: cleaned,
            at: when,
            location: location.flatMap { $0.isEmpty ? nil : $0 }
        )
        do {
            try await itineraryRepository.add(item, toRequest: request.id)
            itineraryItems.append(item)
            Haptics.shared.notification(.success)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    /// Removes one. The rules allow its author or the trip's creator; the button follows the same
    /// rule so nobody is offered an action the server will refuse.
    func removeItineraryItem(_ item: ItineraryItem) async {
        guard canRemove(item) else { return }
        do {
            try await itineraryRepository.remove(itemID: item.id, fromRequest: request.id)
            itineraryItems.removeAll { $0.id == item.id }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func canRemove(_ item: ItineraryItem) -> Bool {
        guard let currentUserID else { return false }
        return item.authorID == currentUserID || request.creatorID == currentUserID
    }

    /// The span the time picker may choose from.
    ///
    /// Bounded by the trip, so nobody can add something to a day the trip does not have — which
    /// is how an item gets stranded the moment it is created, rather than by a later date change.
    var itineraryDayRange: ClosedRange<Date>? {
        guard let start = request.proposedTime, let finish = request.effectiveEndTime,
              finish >= start else { return nil }
        var calendar = Calendar.current
        calendar.timeZone = request.displayTimeZone
        let firstMorning = calendar.startOfDay(for: start)
        let lastNight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: finish))
        return firstMorning...(lastNight ?? finish)
    }

    /// "8:00 PM", on the plan's clock — the same rule the header follows. An item with no time
    /// says so rather than showing midnight, which is what a plain format would render.
    func timeLabel(for item: ItineraryItem) -> String {
        guard let at = item.at else { return "Any time" }
        return at.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, timeZone: request.displayTimeZone)
        )
    }

    /// "Tue 12 May" for a day heading, on the plan's clock for the same reason.
    func dayLabel(for day: ItineraryDay) -> String {
        day.date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: request.displayTimeZone)
        )
    }
}
