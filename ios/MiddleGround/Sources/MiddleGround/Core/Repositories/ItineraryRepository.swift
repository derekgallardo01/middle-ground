import Foundation

/// What is on which day of a trip.
///
/// A subcollection, for the reasons set out on `ItineraryItem`: a five-day trip with four people
/// adding items is exactly the shape that pushes the request document towards its 1 MB ceiling,
/// and every read of the plan would otherwise carry the whole itinerary whether or not anybody
/// opened it.
///
/// `fetch` rather than `observe`, unlike the conversation. A chat is watched together in real
/// time; an itinerary is arranged over days and read when the screen opens. Live-updating it
/// would buy a listener per open trip to show something that changes a handful of times a week.
protocol ItineraryRepository: Sendable {
    func items(forRequest requestID: String) async throws -> [ItineraryItem]

    /// Independent documents, so two people adding at once cannot overwrite each other — the
    /// failure the negotiation chain needed a transaction to avoid.
    func add(_ item: ItineraryItem, toRequest requestID: String) async throws

    /// Correcting a time or a title. Unlike a message, an item is editable: a time that moved is
    /// a correction, not a revision of something people already read and acted on.
    func update(_ item: ItineraryItem, inRequest requestID: String) async throws

    /// By its author, or by whoever owns the trip — `firestore.rules` is the enforcement.
    func remove(itemID: String, fromRequest requestID: String) async throws
}

// MARK: - Mock

actor MockItineraryRepository: ItineraryRepository {
    private var storage: [String: [ItineraryItem]]

    init(seed: [String: [ItineraryItem]] = MockItineraryRepository.samples) {
        storage = seed
    }

    /// A day and a half of the Barcelona trip, so mock mode renders a real itinerary.
    ///
    /// Fixtures matter more here than usual: the group energy card and the trip date range were
    /// both invisible in every screenshot until something reached the state they are for, and an
    /// empty itinerary looks identical to a broken one.
    static let samples: [String: [ItineraryItem]] = [
        "req_8": [
            ItineraryItem(
                id: "itin_1",
                authorID: "user_1",
                title: "Flights land",
                at: PreviewClock.trip(daysFromNow: 26, hour: 15, minute: 40),
                location: "BCN",
                createdAt: Date().addingTimeInterval(-86_400 * 3)
            ),
            ItineraryItem(
                id: "itin_2",
                authorID: "user_2",
                title: "Dinner at Bar Cañete",
                at: PreviewClock.trip(daysFromNow: 26, hour: 21),
                location: "Carrer de la Unió, 17",
                createdAt: Date().addingTimeInterval(-86_400 * 2)
            ),
            ItineraryItem(
                id: "itin_3",
                authorID: "user_3",
                title: "Sagrada Família — tickets booked",
                at: PreviewClock.trip(daysFromNow: 27, hour: 10, minute: 30),
                createdAt: Date().addingTimeInterval(-86_400)
            ),
            // Deliberately without a time: "somewhere for lunch" is a real thing to agree on, and
            // it is the case that gets filed under day one by anything that assumes a time.
            ItineraryItem(
                id: "itin_4",
                authorID: "user_1",
                title: "Somewhere for lunch on the last day",
                createdAt: Date().addingTimeInterval(-3_600)
            )
        ]
    ]

    func items(forRequest requestID: String) async throws -> [ItineraryItem] {
        storage[requestID] ?? []
    }

    func add(_ item: ItineraryItem, toRequest requestID: String) async throws {
        storage[requestID, default: []].append(item)
    }

    func update(_ item: ItineraryItem, inRequest requestID: String) async throws {
        guard let index = storage[requestID]?.firstIndex(where: { $0.id == item.id }) else { return }
        storage[requestID]?[index] = item
    }

    func remove(itemID: String, fromRequest requestID: String) async throws {
        storage[requestID]?.removeAll { $0.id == itemID }
    }
}
