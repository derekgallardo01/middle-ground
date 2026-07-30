import Foundation
import FirebaseFirestore

actor FirestoreRelationshipRepository: RelationshipRepository {
    private let db = Firestore.firestore()
    private let collection = "relationships"
    private static let inviteCollection = "invites"

    func fetchRelationships(for userID: String) async throws -> [Relationship] {
        let snapshot = try await db
            .collection(collection)
            .whereField("participantIDs", arrayContains: userID)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { try? $0.data(as: RelationshipDTO.self).toModel() }
    }

    func saveRelationship(_ relationship: Relationship) async throws {
        let dto = RelationshipDTO(from: relationship)
        let batch = db.batch()

        try batch.setData(from: dto, forDocument: db.collection(collection).document(relationship.id), merge: true)

        // Invite codes live in their own collection keyed by the code itself. Security rules
        // allow `get` but deny `list`, so a code can be redeemed by someone who was told it
        // but cannot be discovered by enumerating relationships.
        batch.setData(
            [
                "relationshipID": relationship.id,
                "ownerID": relationship.participantIDs.first ?? "",
                "createdAt": Timestamp(date: relationship.createdAt)
            ],
            forDocument: db.collection(Self.inviteCollection).document(relationship.inviteCode),
            merge: true
        )

        try await batch.commit()
    }

    func relationship(withInviteCode code: String) async throws -> Relationship? {
        let normalized = Relationship.normalizeInviteCode(code)
        guard !normalized.isEmpty else { return nil }

        let inviteDoc = try await db.collection(Self.inviteCollection).document(normalized).getDocument()
        guard inviteDoc.exists, let relationshipID = inviteDoc.data()?["relationshipID"] as? String else {
            return nil
        }

        let document = try await db.collection(collection).document(relationshipID).getDocument()
        return try? document.data(as: RelationshipDTO.self).toModel()
    }
}
