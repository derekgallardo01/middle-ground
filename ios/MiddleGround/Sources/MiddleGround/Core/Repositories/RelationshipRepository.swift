import Foundation

protocol RelationshipRepository: Sendable {
    func fetchRelationships(for userID: String) async throws -> [Relationship]
    func saveRelationship(_ relationship: Relationship) async throws
    /// Looks up a relationship by its shareable invite code, for the join-a-partner flow.
    func relationship(withInviteCode code: String) async throws -> Relationship?
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

    func relationship(withInviteCode code: String) async throws -> Relationship? {
        relationships.first { $0.inviteCode == Relationship.normalizeInviteCode(code) }
    }
}
