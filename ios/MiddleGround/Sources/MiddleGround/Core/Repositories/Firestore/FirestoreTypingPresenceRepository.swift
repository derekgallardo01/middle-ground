import FirebaseFirestore
import Foundation

actor FirestoreTypingPresenceRepository: TypingPresenceRepository {
    nonisolated private func collection(_ requestID: String) -> CollectionReference {
        Firestore.firestore().collection("requests").document(requestID).collection("presence")
    }

    nonisolated func observeTyping(
        forRequest requestID: String,
        excluding userID: String
    ) -> AsyncStream<[TypingPresence]> {
        AsyncStream { continuation in
            let listener = collection(requestID).addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                // Filtered on read as well as by TTL. Firestore promises TTL deletion *within*
                // 24 hours, not on the second, and an eight-second flag left visible for a day
                // is exactly the lie this feature must not tell.
                let typing = snapshot.documents
                    .compactMap { try? $0.data(as: TypingPresenceDTO.self).toModel(userID: $0.documentID) }
                    .filter { $0.userID != userID && !$0.hasExpired() }
                    .sorted { $0.startedAt < $1.startedAt }
                continuation.yield(typing)
            }
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    /// Deliberately swallows failures and returns nothing.
    ///
    /// A dropped heartbeat costs a flicker. Surfacing it would put an error on screen for the
    /// least important thing the app does, in the middle of someone typing.
    func startTyping(userID: String, forRequest requestID: String) async {
        let presence = TypingPresence(userID: userID)
        try? collection(requestID)
            .document(userID)
            .setData(from: TypingPresenceDTO(from: presence))
    }

    func stopTyping(userID: String, forRequest requestID: String) async {
        try? await collection(requestID).document(userID).delete()
    }
}

/// `userID` is the document ID, so it is not repeated in the body — the rules pin writes to
/// `uid() == userId`, and a second copy would be another thing to keep in step.
private struct TypingPresenceDTO: Codable {
    var startedAt: Timestamp
    var expiresAt: Timestamp

    init(from presence: TypingPresence) {
        startedAt = Timestamp(date: presence.startedAt)
        expiresAt = Timestamp(date: presence.expiresAt)
    }

    func toModel(userID: String) -> TypingPresence {
        TypingPresence(
            userID: userID,
            startedAt: startedAt.dateValue(),
            expiresAt: expiresAt.dateValue()
        )
    }
}
