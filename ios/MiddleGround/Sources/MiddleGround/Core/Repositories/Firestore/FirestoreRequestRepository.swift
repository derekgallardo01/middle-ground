import Foundation
import FirebaseFirestore

actor FirestoreRequestRepository: RequestRepository {
    private let db = Firestore.firestore()
    private static let collection = "requests"

    func fetchRequests(for userID: String) async throws -> [Request] {
        let snapshot = try await db
            .collection(Self.collection)
            // Single array-contains on the denormalised membership field.
            //
            // An OR of (creatorID == uid, recipientIDs contains uid) was DENIED at runtime:
            // security rules authorise reads by `allParticipantIDs`, and Firestore only
            // permits a list query when the query's own constraints prove every match is
            // readable. Filtering the same field the rule checks makes it provable — and
            // needs one composite index instead of two.
            .whereField("allParticipantIDs", arrayContains: userID)
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

    private static let inviteCollection = "invites"

    /// Publishes the invite alongside the code already written on the request.
    ///
    /// Same collection and same shape as group invites: `get` is allowed so a code you were
    /// told can be redeemed, `list` is denied so codes cannot be enumerated.
    func publishPlanInvite(code: String, requestID: String, ownerID: String) async throws {
        try await db.collection(Self.inviteCollection).document(code).setData([
            "requestID": requestID,
            "ownerID": ownerID,
            "createdAt": Timestamp(date: Date())
        ], merge: true)
    }

    func planInvite(forCode code: String) async throws -> String? {
        let document = try await db.collection(Self.inviteCollection).document(code).getDocument()
        guard document.exists else { return nil }
        return document.data()?["requestID"] as? String
    }

    /// `arrayUnion` on both membership arrays and nothing else, which is exactly the shape
    /// `isJoiningPlan` accepts — every other field stays byte-identical, so its immutability
    /// guards hold.
    func addParticipant(_ userID: String, to requestID: String) async throws {
        try await db.collection(Self.collection).document(requestID).updateData([
            "recipientIDs": FieldValue.arrayUnion([userID]),
            "allParticipantIDs": FieldValue.arrayUnion([userID])
        ])
    }

    func deleteRequest(_ request: Request) async throws {
        try await db.collection(Self.collection).document(request.id).delete()
    }

    nonisolated func observeRequests(for userID: String) -> AsyncStream<[Request]> {
        let db = Firestore.firestore()
        return AsyncStream { continuation in
            let listener = db
                .collection(Self.collection)
                .whereField("allParticipantIDs", arrayContains: userID)
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
