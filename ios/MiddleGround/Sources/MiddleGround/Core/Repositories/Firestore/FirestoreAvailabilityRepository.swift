import FirebaseFirestore
import Foundation

actor FirestoreAvailabilityRepository: AvailabilityRepository {
    nonisolated private func collection(_ groupID: String) -> CollectionReference {
        Firestore.firestore()
            .collection("relationships")
            .document(groupID)
            .collection("availability")
    }

    func availability(forGroup groupID: String) async throws -> [SharedAvailability] {
        let snapshot = try await collection(groupID).getDocuments()
        return snapshot.documents.compactMap {
            try? $0.data(as: AvailabilityDTO.self).toModel(userID: $0.documentID)
        }
    }

    nonisolated func observeAvailability(
        forGroup groupID: String
    ) -> AsyncStream<[SharedAvailability]> {
        AsyncStream { continuation in
            let listener = collection(groupID).addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                continuation.yield(
                    snapshot.documents.compactMap {
                        try? $0.data(as: AvailabilityDTO.self).toModel(userID: $0.documentID)
                    }
                )
            }
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    func save(_ availability: SharedAvailability, forGroup groupID: String) async throws {
        try collection(groupID)
            .document(availability.userID)
            .setData(from: AvailabilityDTO(from: availability))
    }
}

/// `userID` is the document ID, so it is not repeated in the body — the rules pin writes to
/// `uid() == userId`, and a second copy would be another thing to keep in step.
private struct AvailabilityDTO: Codable {
    var blocks: [BlockDTO]
    var updatedAt: Timestamp

    struct BlockDTO: Codable {
        var id: String
        var start: Timestamp
        var end: Timestamp
        var isAllDay: Bool
    }

    init(from availability: SharedAvailability) {
        blocks = availability.blocks.map {
            BlockDTO(
                id: $0.id,
                start: Timestamp(date: $0.start),
                end: Timestamp(date: $0.end),
                isAllDay: $0.isAllDay
            )
        }
        updatedAt = Timestamp(date: availability.updatedAt)
    }

    func toModel(userID: String) -> SharedAvailability {
        SharedAvailability(
            userID: userID,
            blocks: blocks.map {
                UnavailableBlock(
                    id: $0.id,
                    start: $0.start.dateValue(),
                    end: $0.end.dateValue(),
                    isAllDay: $0.isAllDay
                )
            },
            updatedAt: updatedAt.dateValue()
        )
    }
}
