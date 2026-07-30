import Foundation
import FirebaseFirestore

actor FirestoreRequestRepository: RequestRepository {
    private let db = Firestore.firestore()
    private static let collection = "requests"

    func fetchRequests(for userID: String) async throws -> [Request] {
        let snapshot = try await db
            .collection(Self.collection)
            .whereFilter(Filter.orFilter([
                Filter.whereField("creatorID", isEqualTo: userID),
                Filter.whereField("recipientIDs", arrayContains: userID)
            ]))
            .order(by: "updatedAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { try? $0.data(as: RequestDTO.self).toModel() }
    }

    func createRequest(_ request: Request) async throws {
        let dto = RequestDTO(from: request)
        try db.collection(Self.collection).document(request.id).setData(from: dto)
    }

    func updateRequest(_ request: Request) async throws {
        let dto = RequestDTO(from: request)
        try db.collection(Self.collection).document(request.id).setData(from: dto, merge: true)
    }

    func deleteRequest(_ request: Request) async throws {
        try await db.collection(Self.collection).document(request.id).delete()
    }

    nonisolated func observeRequests(for userID: String) -> AsyncStream<[Request]> {
        let db = Firestore.firestore()
        return AsyncStream { continuation in
            let listener = db
                .collection(Self.collection)
                .whereFilter(Filter.orFilter([
                    Filter.whereField("creatorID", isEqualTo: userID),
                    Filter.whereField("recipientIDs", arrayContains: userID)
                ]))
                .order(by: "updatedAt", descending: true)
                .addSnapshotListener { snapshot, _ in
                    guard let snapshot else {
                        continuation.finish()
                        return
                    }
                    let requests = snapshot.documents.compactMap { try? $0.data(as: RequestDTO.self).toModel() }
                    continuation.yield(requests)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }
}
