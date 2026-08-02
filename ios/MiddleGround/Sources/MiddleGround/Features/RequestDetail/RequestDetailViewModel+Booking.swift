import Foundation

/// Booking a table for a plan that is already agreed.
///
/// The half of the restaurants idea that needs nobody's permission: the plan already knows the
/// place, the time and how many people are coming, so the one useful thing left is a link that
/// does not make anybody type it in again. It appears only on a plan that is actually agreed —
/// offering to book a table for something still being argued over is putting the cart first.
///
/// Split out of `RequestDetailViewModel`, which was already at the 500-line limit, for the same
/// reason `RequestEnums` was split out of `Request`. The stored `bookingURL` stays on the class
/// because Swift does not allow stored properties in an extension.
extension RequestDetailViewModel {
    var canBookTable: Bool { bookingURL != nil }

    /// The place as it will appear on the button, so the label names somewhere real.
    var bookingPlaceName: String? {
        guard let trimmed = request.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    func loadBookingLink() async {
        guard request.status == .accepted,
              reservations.capabilities.contains(.link),
              let place = bookingPlaceName else {
            bookingURL = nil
            return
        }

        // The plan's "Where?" is free text. If it happens to name somewhere on the curated list we
        // use that entry, which spells the name the way the booking site does; otherwise the raw
        // text is a better guess than nothing.
        let partySize = request.allParticipantIDs.count
        let matches = (try? await reservations.search(
            near: place, partySize: partySize, at: request.proposedTime
        )) ?? []
        let venue = matches.first {
            $0.name.localizedCaseInsensitiveCompare(place) == .orderedSame
        } ?? ReservableVenue(
            name: place, city: "", providerID: reservations.id, providerVenueID: ""
        )

        bookingURL = reservations.bookingURL(
            for: venue, partySize: partySize, at: request.proposedTime
        )
    }

    /// Called when the link is actually followed, not when it is merely shown — an impression is
    /// not intent, and the whole value of this record is that it means somebody wanted a table.
    func recordBookingIntent() async {
        await planOutcomes.recordBookingIntent(.from(request, provider: reservations.id))
    }
}
