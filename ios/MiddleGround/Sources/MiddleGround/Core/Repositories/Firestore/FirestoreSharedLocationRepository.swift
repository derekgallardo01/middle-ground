import FirebaseFirestore
import Foundation

actor FirestoreSharedLocationRepository: SharedLocationRepository {
    /// Computed, not stored: constructing this type must not require FirebaseApp.configure().
    private var db: Firestore { Firestore.firestore() }

    private func collection(_ requestID: String) -> CollectionReference {
        db.collection("requests").document(requestID).collection("locations")
    }

    /// Expired points are filtered here as well as deleted by TTL.
    ///
    /// Firestore promises TTL deletion *within 24 hours*, not at the instant, so a lapsed point
    /// can still be readable for a while. Showing where somebody was last night because a
    /// background job has not run yet is exactly the failure this feature must not have.
    func locations(forRequest requestID: String) async throws -> [SharedLocation] {
        let snapshot = try await collection(requestID).getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: SharedLocationDTO.self).toModel(userID: $0.documentID) }
            .filter { !$0.hasExpired }
    }

    func share(_ location: SharedLocation, forRequest requestID: String) async throws {
        try collection(requestID)
            .document(location.userID)
            .setData(from: SharedLocationDTO(from: location))
    }

    func stopSharing(userID: String, forRequest requestID: String) async throws {
        try await collection(requestID).document(userID).delete()
    }
}

/// `userID` is the document ID, so it is not stored in the body — the rules pin writes to
/// `uid() == userId`, and a second copy in the data would be a second thing to keep in step.
private struct SharedLocationDTO: Codable {
    var latitude: Double
    var longitude: Double
    var sharedAt: Date
    var expiresAt: Date

    init(from location: SharedLocation) {
        latitude = location.latitude
        longitude = location.longitude
        sharedAt = location.sharedAt
        expiresAt = location.expiresAt
    }

    func toModel(userID: String) -> SharedLocation {
        SharedLocation(
            userID: userID,
            latitude: latitude,
            longitude: longitude,
            sharedAt: sharedAt,
            expiresAt: expiresAt
        )
    }
}
