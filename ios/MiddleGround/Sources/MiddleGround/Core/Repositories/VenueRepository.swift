import Foundation

/// The curated venue list.
///
/// Readable by anyone signed in, writable only by an admin — the same shape as any editorial
/// list. Nothing here is personal data, which is why it can be world-readable inside the app
/// without the usual participant checks.
protocol VenueRepository: Sendable {
    func venues() async throws -> [Venue]
    /// Admin-only; denied to everyone else by `firestore.rules`.
    func save(_ venue: Venue) async throws
    func delete(id: String) async throws
}

actor MockVenueRepository: VenueRepository {
    private var storage: [String: Venue]

    init(seed: [Venue] = MockVenueRepository.samples) {
        storage = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    static let samples = [
        Venue(
            id: "v1",
            name: "Lucia's",
            city: "Brooklyn",
            categories: [.dating, .relationship],
            emoji: "🍝",
            rank: 0
        ),
        Venue(id: "v2", name: "Prospect Park", city: "Brooklyn", emoji: "🌳", rank: 1),
        Venue(
            id: "v3",
            name: "The Anchor",
            city: "Brooklyn",
            categories: [.friends],
            emoji: "🍸",
            rank: 2
        )
    ]

    func venues() async throws -> [Venue] {
        storage.values.sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }
    }

    func save(_ venue: Venue) async throws {
        storage[venue.id] = venue
    }

    func delete(id: String) async throws {
        storage[id] = nil
    }
}
