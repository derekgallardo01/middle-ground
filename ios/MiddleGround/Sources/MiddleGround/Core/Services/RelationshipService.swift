import Foundation
import Factory

/// Owns relationship creation and the invite-code pairing flow.
///
/// Pairing is what makes the rest of the app usable: a request needs a recipient, and a
/// recipient only exists once a second person has joined the creator's relationship.
actor RelationshipService {
    private let repository: RelationshipRepository
    private let userRepository: UserRepository
    private let analytics = Container.shared.analyticsService()

    init(repository: RelationshipRepository, userRepository: UserRepository) {
        self.repository = repository
        self.userRepository = userRepository
    }

    enum PairingError: LocalizedError, Equatable {
        case codeNotFound
        case alreadyJoined
        case ownCode

        var errorDescription: String? {
            switch self {
            case .codeNotFound:
                return "We couldn't find that code. Double-check it and try again."
            case .alreadyJoined:
                return "You're already part of this group."
            case .ownCode:
                return "That's your own code — share it with someone else to pair."
            }
        }
    }

    func relationships(for userID: String) async throws -> [Relationship] {
        try await repository.fetchRelationships(for: userID)
    }

    /// Creates a relationship owned by `ownerID` with a fresh invite code to share.
    func createRelationship(type: RelationshipType, ownerID: String) async throws -> Relationship {
        let relationship = Relationship(
            id: UUID().uuidString,
            participantIDs: [ownerID],
            type: type
        )
        try await repository.saveRelationship(relationship)
        await analytics.track(
            .relationshipCreated,
            userID: ownerID,
            relationshipID: relationship.id,
            metadata: ["type": type.rawValue]
        )
        return relationship
    }

    /// Adds `userID` to the relationship identified by `code`.
    ///
    /// Works entirely from the invite document: the joiner cannot read the relationship until
    /// they are a member of it, so membership checks are done against their *own*
    /// relationships instead.
    func join(inviteCode code: String, userID: String) async throws -> Relationship {
        guard let invite = try await repository.invite(forCode: code) else {
            throw PairingError.codeNotFound
        }
        if invite.ownerID == userID {
            throw PairingError.ownCode
        }

        let existing = try await repository.fetchRelationships(for: userID)
        if existing.contains(where: { $0.id == invite.relationshipID }) {
            throw PairingError.alreadyJoined
        }

        try await repository.addParticipant(userID, to: invite.relationshipID)

        // Now a participant, so the relationship is readable.
        let joined = try await repository.fetchRelationships(for: userID)
        guard let relationship = joined.first(where: { $0.id == invite.relationshipID }) else {
            throw PairingError.codeNotFound
        }
        await analytics.track(.inviteRedeemed, userID: userID, relationshipID: relationship.id)
        return relationship
    }

    /// Removes `userID` from a group.
    ///
    /// This is the only way out of a group short of deleting your account, so it is also what
    /// backs the "block an abusive user" requirement in App Review guideline 1.2.
    ///
    /// If the leaver owns the invite code, it is revoked: leaving drops the group back to a
    /// single member, which is precisely the state `isRedeemingInvite` accepts, so a live code
    /// would let anyone holding it walk into the group of the person who stayed.
    func leave(relationshipID: String, userID: String) async throws {
        let mine = try await repository.fetchRelationships(for: userID)
        let relationship = mine.first { $0.id == relationshipID }
        let ownsInvite = relationship?.participantIDs.first == userID

        try await repository.removeParticipant(userID, from: relationshipID)

        if ownsInvite, let code = relationship?.inviteCode {
            // Best-effort: having left is the user-visible outcome, and a failure here must not
            // make it look like leaving failed. The stale code is repaired by `repairInvite`
            // on the remaining member's next Profile load.
            try? await repository.revokeInvite(code: code)
        }

        await analytics.track(.relationshipLeft, userID: userID, relationshipID: relationshipID)
    }

    /// Issues a new shareable code and retires the old one.
    ///
    /// Codes never expired and were never deleted after pairing, so anyone who saw one kept
    /// indefinite access. This is the manual revocation path.
    @discardableResult
    func regenerateInviteCode(for relationship: Relationship, userID: String) async throws -> String {
        let newCode = Relationship.generateInviteCode()
        try await repository.rotateInviteCode(
            to: newCode,
            from: relationship.inviteCode,
            relationshipID: relationship.id,
            ownerID: userID
        )
        return newCode
    }

    /// Republishes the invite document if the relationship's code no longer resolves.
    ///
    /// Reachable when the code's owner left: they revoked it on the way out, leaving the
    /// remaining member holding a code that Profile still displays but nobody can redeem.
    /// Returns the working code, which may be a new one.
    @discardableResult
    func repairInvite(for relationship: Relationship, userID: String) async throws -> String {
        guard relationship.participantIDs.first == userID else { return relationship.inviteCode }
        if try await repository.invite(forCode: relationship.inviteCode) != nil {
            return relationship.inviteCode
        }
        let newCode = Relationship.generateInviteCode()
        try await repository.rotateInviteCode(
            to: newCode,
            from: nil,
            relationshipID: relationship.id,
            ownerID: userID
        )
        return newCode
    }

    /// Resolves a display label per relationship: the partner's name when known,
    /// falling back to the relationship type so the UI never shows an empty row.
    func displayLabels(for relationships: [Relationship], currentUserID: String) async -> [String: String] {
        var labels: [String: String] = [:]
        for relationship in relationships {
            if let partnerID = relationship.partnerID(excluding: currentUserID),
               let partner = try? await userRepository.user(id: partnerID),
               !partner.name.isEmpty {
                labels[relationship.id] = partner.name
            } else {
                labels[relationship.id] = relationship.type.displayName
            }
        }
        return labels
    }
}
