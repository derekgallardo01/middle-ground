import Foundation

protocol RelationshipRepository: Sendable {
    func fetchRelationships(for userID: String) async throws -> [Relationship]
    func saveRelationship(_ relationship: Relationship) async throws
    /// Resolves a shareable invite code to its target, for the join-a-partner flow.
    func invite(forCode code: String) async throws -> RelationshipInvite?

    /// Adds a participant, touching *only* `participantIDs`.
    ///
    /// Joining must not rewrite the whole document: the DTO round-trips `createdAt` through
    /// `Date`, losing the stored Timestamp's nanoseconds, so a full write changes the value
    /// and trips the `immutable('createdAt')` guard in firestore.rules.
    func addParticipant(_ userID: String, to relationshipID: String) async throws
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

    func invite(forCode code: String) async throws -> RelationshipInvite? {
        let normalized = Relationship.normalizeInviteCode(code)
        guard let match = relationships.first(where: { $0.inviteCode == normalized }),
              let ownerID = match.participantIDs.first else { return nil }
        return RelationshipInvite(code: normalized, relationshipID: match.id, ownerID: ownerID)
    }

    func addParticipant(_ userID: String, to relationshipID: String) async throws {
        guard let index = relationships.firstIndex(where: { $0.id == relationshipID }) else { return }
        if !relationships[index].participantIDs.contains(userID) {
            relationships[index].participantIDs.append(userID)
        }
    }
}
