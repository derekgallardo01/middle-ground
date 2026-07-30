import Foundation

/// Owns relationship creation and the invite-code pairing flow.
///
/// Pairing is what makes the rest of the app usable: a request needs a recipient, and a
/// recipient only exists once a second person has joined the creator's relationship.
actor RelationshipService {
    private let repository: RelationshipRepository
    private let userRepository: UserRepository

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
        return relationship
    }

    /// Adds `userID` to the relationship identified by `code`.
    func join(inviteCode code: String, userID: String) async throws -> Relationship {
        guard var relationship = try await repository.relationship(withInviteCode: code) else {
            throw PairingError.codeNotFound
        }
        if relationship.participantIDs.contains(userID) {
            throw relationship.participantIDs.count == 1 ? PairingError.ownCode : PairingError.alreadyJoined
        }

        relationship.participantIDs.append(userID)
        try await repository.saveRelationship(relationship)
        return relationship
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
