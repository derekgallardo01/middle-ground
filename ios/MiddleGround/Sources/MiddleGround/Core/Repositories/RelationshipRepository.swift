import Foundation

protocol RelationshipRepository: Sendable {
    func fetchRelationships(for userID: String) async throws -> [Relationship]
    func saveRelationship(_ relationship: Relationship) async throws
}

actor MockRelationshipRepository: RelationshipRepository {
    private var relationships: [Relationship] = [.preview]
    
    func fetchRelationships(for userID: String) async throws -> [Relationship] {
        relationships.filter { $0.participantIDs.contains(userID) }
    }
    
    func saveRelationship(_ relationship: Relationship) async throws {
        if let index = relationships.firstIndex(where: { $0.id == relationship.id }) {
            relationships[index] = relationship
        } else {
            relationships.append(relationship)
        }
    }
}
