import Foundation
import FirebaseAuth
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
        let ownerID = relationship.participantIDs.first
        let isOwner = ownerID != nil && ownerID == Auth.auth().currentUser?.uid

        let batch = db.batch()
        try batch.setData(from: dto, forDocument: db.collection(collection).document(relationship.id), merge: true)

        // Invite codes live in their own collection keyed by the code itself. Security rules
        // allow `get` but deny `list`, so a code can be redeemed by someone who was told it
        // but cannot be discovered by enumerating relationships.
        //
        // Only the owner writes this document. Writing it unconditionally meant a *joiner's*
        // batch included an invite write whose `ownerID` was somebody else's uid, which the
        // rules correctly reject — taking the whole batch, and therefore pairing, down with it.
        if isOwner {
            batch.setData(
                [
                    "relationshipID": relationship.id,
                    "ownerID": ownerID ?? "",
                    "createdAt": Timestamp(date: relationship.createdAt)
                ],
                forDocument: db.collection(Self.inviteCollection).document(relationship.inviteCode),
                merge: true
            )
        }

        try await batch.commit()
    }

    func addParticipant(_ userID: String, to relationshipID: String) async throws {
        // arrayUnion appends, which is exactly what `isRedeemingInvite` in firestore.rules
        // expects (`participantIDs == old.concat([uid()])`), and it leaves every other field
        // byte-identical so the immutability guards hold.
        try await db.collection(collection).document(relationshipID).updateData([
            "participantIDs": FieldValue.arrayUnion([userID])
        ])
    }

    func removeParticipant(_ userID: String, from relationshipID: String) async throws {
        // arrayRemove is the mirror of addParticipant: `isLeaving` in firestore.rules checks
        // `participantIDs == old.removeAll([uid()])`, and every other field stays byte-identical
        // so the immutability guards hold.
        try await db.collection(collection).document(relationshipID).updateData([
            "participantIDs": FieldValue.arrayRemove([userID])
        ])
    }

    func rotateInviteCode(
        to newCode: String,
        from oldCode: String?,
        relationshipID: String,
        ownerID: String
    ) async throws {
        let batch = db.batch()

        // Only `inviteCode` moves. A full DTO write would change `createdAt` (Timestamp →
        // Date loses nanoseconds) and be refused by the rules.
        batch.updateData(
            ["inviteCode": newCode],
            forDocument: db.collection(collection).document(relationshipID)
        )

        batch.setData(
            [
                "relationshipID": relationshipID,
                "ownerID": ownerID,
                "createdAt": Timestamp(date: Date())
            ],
            forDocument: db.collection(Self.inviteCollection).document(newCode),
            merge: true
        )

        // Retiring the old document is the point: without it the previous code keeps working
        // forever, and a code shared with someone you have since removed still lets them in.
        if let oldCode, oldCode != newCode {
            batch.deleteDocument(db.collection(Self.inviteCollection).document(oldCode))
        }

        try await batch.commit()
    }

    func revokeInvite(code: String) async throws {
        try await db.collection(Self.inviteCollection).document(code).delete()
    }

    func invite(forCode code: String) async throws -> RelationshipInvite? {
        let normalized = Relationship.normalizeInviteCode(code)
        guard !normalized.isEmpty else { return nil }

        // Only the invite document is read. Reading the relationship itself would be denied:
        // `allow get` requires membership, which the person joining does not have yet.
        let inviteDoc = try await db.collection(Self.inviteCollection).document(normalized).getDocument()
        guard inviteDoc.exists,
              let data = inviteDoc.data(),
              let relationshipID = data["relationshipID"] as? String,
              let ownerID = data["ownerID"] as? String else {
            return nil
        }
        return RelationshipInvite(code: normalized, relationshipID: relationshipID, ownerID: ownerID)
    }
}
