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

    /// Removes a participant, touching *only* `participantIDs`. Same nanosecond reasoning
    /// as `addParticipant` — this is an `arrayRemove`, not a document rewrite.
    func removeParticipant(_ userID: String, from relationshipID: String) async throws

    /// Points a fresh code at a relationship and retires the previous one.
    ///
    /// Pass `from: nil` to publish a code that has no invite document yet — which is how the
    /// remaining member repairs their group after the code's owner left and revoked it.
    func rotateInviteCode(
        to newCode: String,
        from oldCode: String?,
        relationshipID: String,
        ownerID: String
    ) async throws

    /// Retires a code without issuing a replacement. Only the code's owner may do this.
    ///
    /// Needed when the owner *leaves*: the group drops back to one member, which is exactly
    /// the state `isRedeemingInvite` accepts, so an un-revoked code would let anyone holding
    /// it join the person who stayed behind.
    func revokeInvite(code: String) async throws
}

actor MockRelationshipRepository: RelationshipRepository {
    private var relationships: [Relationship] = [.preview]
    /// Mirrors the deletion of an `invites/{code}` document, so `invite(forCode:)` stops
    /// resolving a retired code exactly as Firestore would.
    private var revokedCodes: Set<String> = []

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
        guard !revokedCodes.contains(normalized),
              let match = relationships.first(where: { $0.inviteCode == normalized }),
              let ownerID = match.participantIDs.first else { return nil }
        return RelationshipInvite(code: normalized, relationshipID: match.id, ownerID: ownerID)
    }

    func addParticipant(_ userID: String, to relationshipID: String) async throws {
        guard let index = relationships.firstIndex(where: { $0.id == relationshipID }) else { return }
        if !relationships[index].participantIDs.contains(userID) {
            relationships[index].participantIDs.append(userID)
        }
    }

    func removeParticipant(_ userID: String, from relationshipID: String) async throws {
        guard let index = relationships.firstIndex(where: { $0.id == relationshipID }) else { return }
        relationships[index].participantIDs.removeAll { $0 == userID }
    }

    func rotateInviteCode(
        to newCode: String,
        from oldCode: String?,
        relationshipID: String,
        ownerID: String
    ) async throws {
        guard let index = relationships.firstIndex(where: { $0.id == relationshipID }) else { return }
        relationships[index].inviteCode = newCode
        revokedCodes.remove(newCode)
        if let oldCode { revokedCodes.insert(oldCode) }
    }

    func revokeInvite(code: String) async throws {
        revokedCodes.insert(code)
    }
}
