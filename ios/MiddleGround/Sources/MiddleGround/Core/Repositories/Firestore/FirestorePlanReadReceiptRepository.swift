import FirebaseFirestore
import Foundation

actor FirestorePlanReadReceiptRepository: PlanReadReceiptRepository {
    nonisolated private func collection(_ requestID: String) -> CollectionReference {
        Firestore.firestore().collection("requests").document(requestID).collection("reads")
    }

    nonisolated func observeReceipts(
        forRequest requestID: String,
        excluding userID: String
    ) -> AsyncStream<[PlanReadReceipt]> {
        AsyncStream { continuation in
            let listener = collection(requestID).addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                let receipts = snapshot.documents
                    .compactMap { document -> PlanReadReceipt? in
                        guard let readAt = document.data()["readAt"] as? Timestamp else { return nil }
                        return PlanReadReceipt(userID: document.documentID, readAt: readAt.dateValue())
                    }
                    .filter { $0.userID != userID }
                    .sorted { $0.readAt > $1.readAt }
                continuation.yield(receipts)
            }
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    /// Swallows failures: a lost receipt costs a line of text nobody depends on.
    func markRead(userID: String, forRequest requestID: String) async {
        try? await collection(requestID)
            .document(userID)
            .setData(["readAt": FieldValue.serverTimestamp()], merge: true)
    }
}
