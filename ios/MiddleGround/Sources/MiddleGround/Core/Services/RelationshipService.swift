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
        // `kind` because this event means two different things: joining a group, and joining one
        // plan. They were indistinguishable, so the operator funnel's "Paired" step counted both.
        // `invitedBy` because the edge back to whoever sent the code was in hand and thrown away,
        // which is why "of the invites we sent, how many became a paired user?" had no answer.
        await analytics.track(
            .inviteRedeemed,
            userID: userID,
            relationshipID: relationship.id,
            metadata: ["kind": "group", "invitedBy": invite.ownerID]
        )
        return relationship
    }

    /// Removes `userID` from a group.
    ///
    /// This is the only way out of a group short of deleting your account, so it is also what
    /// backs the "block an abusive user" requirement in App Review guideline 1.2.
    ///
    /// If the leaver owns the invite code, it is revoked. That used to be because leaving
    /// dropped a group back to one member — the only state a join was permitted in. Groups now
    /// hold up to their seat count, so a code is live whenever there is room at all, which makes
    /// revoking it *more* important rather than less: the person who left should not keep a
    /// working key to a group they are no longer in, and the people who stayed should not
    /// inherit an invite they never issued.
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
        // Only the re-issue. A group gets a code the moment it is created, so tracking that too
        // would just be `relationshipCreated` counted twice under another name.
        await analytics.track(
            .inviteCreated,
            userID: userID,
            relationshipID: relationship.id,
            metadata: ["kind": "group"]
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

    /// Resolves a display label per relationship.
    ///
    /// Precedence is name → partner → type. A name the members chose beats a name we inferred:
    /// two groups containing the same person, or two groups of the same type, are otherwise
    /// indistinguishable in the Compose picker. The type remains the last resort so a row is
    /// never blank.
    func displayLabels(for relationships: [Relationship], currentUserID: String) async -> [String: String] {
        var labels: [String: String] = [:]
        for relationship in relationships {
            if let name = relationship.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                labels[relationship.id] = name
                continue
            }

            // Everybody else, not `partnerID`. That returns "an arbitrary one of them" for a
            // group — its own doc comment says so — and this called it anyway, so an unnamed
            // group of three was labelled with one member's name. A plan addressed to three
            // people that says "Sam" is wrong about who is on it.
            let others = relationship.otherIDs(excluding: currentUserID)
            var names: [String] = []
            for id in others {
                if let user = try? await userRepository.user(id: id), !user.name.isEmpty {
                    names.append(user.name)
                }
            }

            labels[relationship.id] = Self.joined(names) ?? relationship.type.displayName
        }
        return labels
    }

    /// "Sam", "Sam & Priya", "Sam, Priya & Jo" — how a person would say a list out loud.
    ///
    /// Beyond three it stops naming everyone: a picker row is one line, and "Sam, Priya, Jo, Ada
    /// & Ben" is a label nobody reads to the end of.
    static func joined(_ names: [String]) -> String? {
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        case 3: return "\(names[0]), \(names[1]) & \(names[2])"
        default: return "\(names[0]), \(names[1]) & \(names.count - 2) others"
        }
    }

    /// Renames a group. Any participant may do this — it is a shared label, not an owner's.
    ///
    /// Needs no security-rule change: the general update branch pins only `inviteCode`, `type`
    /// and `createdAt`, so `name` was always writable by a participant. `RelationshipRulesTests`
    /// asserts that, so it stays true on purpose rather than by omission.
    ///
    /// An all-whitespace name clears the name rather than storing blanks that would render as an
    /// empty row.
    func rename(_ relationship: Relationship, to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = relationship
        updated.name = trimmed.isEmpty ? nil : RequestLimits.clamp(trimmed, to: RequestLimits.groupName)
        try await repository.saveRelationship(updated)
    }
}
