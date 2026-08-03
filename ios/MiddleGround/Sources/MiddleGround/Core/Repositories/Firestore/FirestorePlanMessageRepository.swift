import FirebaseFirestore
import Foundation

actor FirestorePlanMessageRepository: PlanMessageRepository {
    /// Computed, not stored: constructing this type must not require FirebaseApp.configure().
    private var db: Firestore { Firestore.firestore() }

    nonisolated private func collection(_ requestID: String) -> CollectionReference {
        Firestore.firestore().collection("requests").document(requestID).collection("messages")
    }

    /// Newest first on the wire, oldest first in the result.
    ///
    /// The limit has to bite at the *recent* end — ordering ascending and limiting would return
    /// the oldest hundred messages and stop, so a long conversation would show its beginning
    /// forever and never its last line.
    func messages(forRequest requestID: String, limit: Int) async throws -> [PlanMessage] {
        let snapshot = try await collection(requestID)
            .order(by: "at", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: PlanMessageDTO.self).toModel(id: $0.documentID) }
            .reversed()
    }

    nonisolated func observeMessages(
        forRequest requestID: String,
        limit: Int
    ) -> AsyncStream<[PlanMessage]> {
        AsyncStream { continuation in
            let listener = collection(requestID)
                .order(by: "at", descending: true)
                .limit(to: limit)
                .addSnapshotListener { snapshot, error in
                    guard let snapshot else {
                        if let error {
                            MGLog.storage.error(
                                "Messages listener failed: \(error.localizedDescription, privacy: .public)"
                            )
                        }
                        return
                    }
                    let messages = snapshot.documents
                        .compactMap { try? $0.data(as: PlanMessageDTO.self).toModel(id: $0.documentID) }
                        .reversed()
                    continuation.yield(Array(messages))
                }
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    func send(_ message: PlanMessage, forRequest requestID: String) async throws {
        try collection(requestID)
            .document(message.id)
            .setData(from: PlanMessageDTO(from: message))
    }

    func delete(messageID: String, forRequest requestID: String) async throws {
        try await collection(requestID).document(messageID).delete()
    }
}

/// The ID is the document ID, so it is not duplicated in the body.
private struct PlanMessageDTO: Codable {
    var senderID: String
    var text: String
    var parentID: String?
    var at: Timestamp

    init(from message: PlanMessage) {
        senderID = message.senderID
        text = message.text
        parentID = message.parentID
        at = Timestamp(date: message.at)
    }

    func toModel(id: String) -> PlanMessage {
        PlanMessage(
            id: id,
            senderID: senderID,
            text: text,
            parentID: parentID,
            at: at.dateValue()
        )
    }
}
