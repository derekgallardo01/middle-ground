import Foundation
import FirebaseFirestore

actor FirestoreRelationshipRepository: RelationshipRepository {
    private let db = Firestore.firestore()
    private let collection = "relationships"
    
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
        try db.collection(collection).document(relationship.id).setData(from: dto, merge: true)
    }
}
