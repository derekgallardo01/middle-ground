import FirebaseFirestore
import Foundation

actor FirestoreItineraryRepository: ItineraryRepository {
    /// Computed, not stored: constructing this type must not require FirebaseApp.configure().
    private var db: Firestore { Firestore.firestore() }

    nonisolated private func collection(_ requestID: String) -> CollectionReference {
        Firestore.firestore().collection("requests").document(requestID).collection("itinerary")
    }

    /// Everything, ordered by when it was added.
    ///
    /// Unbounded, unlike the conversation: an itinerary is a list somebody wrote on purpose and a
    /// limit would hide the end of a long trip with no way to ask for the rest. Ordered by
    /// `createdAt` rather than `at`, because an item with no time has no `at` — and Firestore
    /// range-orders skip documents missing the field entirely, so ordering by `at` would silently
    /// drop every undated item from the list.
    func items(forRequest requestID: String) async throws -> [ItineraryItem] {
        let snapshot = try await collection(requestID)
            .order(by: "createdAt")
            .getDocuments()
        return snapshot.documents.compactMap {
            try? $0.data(as: ItineraryItemDTO.self).toModel(id: $0.documentID)
        }
    }

    func add(_ item: ItineraryItem, toRequest requestID: String) async throws {
        try collection(requestID)
            .document(item.id)
            .setData(from: ItineraryItemDTO(from: item))
    }

    /// `merge: false` on purpose — the rules pin `authorID` and `createdAt`, and the DTO carries
    /// both, so a whole-document write is checked rather than trusted. A merge could clear `at`
    /// by omission and the rules would have nothing to compare.
    func update(_ item: ItineraryItem, inRequest requestID: String) async throws {
        try collection(requestID)
            .document(item.id)
            .setData(from: ItineraryItemDTO(from: item))
    }

    func remove(itemID: String, fromRequest requestID: String) async throws {
        try await collection(requestID).document(itemID).delete()
    }
}

/// The wire shape. `id` is the document ID and deliberately not a field — `isWellFormed()` in
/// firestore.rules lists the keys it will accept, and an extra one is refused.
private struct ItineraryItemDTO: Codable {
    var authorID: String
    var title: String
    var at: Timestamp?
    var location: String?
    var createdAt: Timestamp

    init(from item: ItineraryItem) {
        authorID = item.authorID
        title = item.title
        at = item.at.map { Timestamp(date: $0) }
        location = item.location
        createdAt = Timestamp(date: item.createdAt)
    }

    func toModel(id: String) -> ItineraryItem {
        ItineraryItem(
            id: id,
            authorID: authorID,
            title: title,
            at: at?.dateValue(),
            location: location,
            createdAt: createdAt.dateValue()
        )
    }
}
