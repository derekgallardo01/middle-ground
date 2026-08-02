import FirebaseFirestore
import Foundation

actor FirestoreVenueRepository: VenueRepository {
    /// Computed, not stored: constructing this type must not require FirebaseApp.configure().
    private var db: Firestore { Firestore.firestore() }
    private static let collection = "venues"

    /// Enough for a suggestion strip; this is read every time the compose sheet opens.
    private static let limit = 100

    func venues() async throws -> [Venue] {
        let snapshot = try await db.collection(Self.collection).limit(to: Self.limit).getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: VenueDTO.self).toModel(id: $0.documentID) }
            .sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }
    }

    func save(_ venue: Venue) async throws {
        try db.collection(Self.collection).document(venue.id).setData(from: VenueDTO(from: venue))
    }

    func delete(id: String) async throws {
        try await db.collection(Self.collection).document(id).delete()
    }
}

/// Categories are stored as raw strings, and an unrecognised one decodes to `.unknown` rather
/// than failing the whole venue — the same trap that made a request in a new category silently
/// vanish on an older build.
///
/// `.unknown` rather than dropped, which matters: an empty category list means "suits every
/// plan", so a venue tagged only with a category this build has never heard of would decode to
/// empty and start being offered for *everything*. Keeping `.unknown` means it matches nothing
/// real instead, which is the safe direction to be wrong in.
private struct VenueDTO: Codable {
    var name: String
    var city: String
    var categories: [String]
    var emoji: String
    var address: String?
    var rank: Int

    init(from venue: Venue) {
        name = venue.name
        city = venue.city
        categories = venue.categories.map(\.rawValue)
        emoji = venue.emoji
        address = venue.address
        rank = venue.rank
    }

    func toModel(id: String) -> Venue {
        Venue(
            id: id,
            name: name,
            city: city,
            categories: categories.map { RequestCategory(rawValue: $0) ?? .unknown },
            emoji: emoji,
            address: address,
            rank: rank
        )
    }
}
