import Foundation
import SwiftData

actor CachedRelationshipRepository: RelationshipRepository {
    private let remote: RelationshipRepository
    private let modelContainer: ModelContainer

    init(remote: RelationshipRepository, modelContainer: ModelContainer) {
        self.remote = remote
        self.modelContainer = modelContainer
    }

    private var context: ModelContext {
        ModelContext(modelContainer)
    }

    /// Remote first, cache as a fallback — the same shape as `CachedRequestRepository`.
    ///
    /// Without the fallback this threw offline, and who you are paired with is upstream of nearly
    /// every screen: no relationships means no partners to choose in Create Request, an empty
    /// calendar, and a profile with nobody in it. All of it already sits in the local store.
    func fetchRelationships(for userID: String) async throws -> [Relationship] {
        do {
            let remoteRelationships = try await remote.fetchRelationships(for: userID)
            try merge(relationships: remoteRelationships)
        } catch {
            MGLog.storage.info("Reading relationships failed; falling back to the cache.")
        }
        return try fetchLocal(for: userID)
    }

    func saveRelationship(_ relationship: Relationship) async throws {
        try await remote.saveRelationship(relationship)
        try merge(relationships: [relationship])
    }

    func addParticipant(_ userID: String, to relationshipID: String) async throws {
        try await remote.addParticipant(userID, to: relationshipID)
    }

    func removeParticipant(_ userID: String, from relationshipID: String) async throws {
        try await remote.removeParticipant(userID, from: relationshipID)
        // The local copy has to go too. `fetchLocal` filters on membership, but the row would
        // otherwise sit in the store and reappear for this user on any later merge.
        let ctx = context
        let descriptor = FetchDescriptor<RelationshipEntity>(predicate: #Predicate { $0.id == relationshipID })
        for entity in try ctx.fetch(descriptor) {
            ctx.delete(entity)
        }
        try ctx.save()
    }

    func rotateInviteCode(
        to newCode: String,
        from oldCode: String?,
        relationshipID: String,
        ownerID: String
    ) async throws {
        try await remote.rotateInviteCode(
            to: newCode, from: oldCode, relationshipID: relationshipID, ownerID: ownerID
        )
        let ctx = context
        let descriptor = FetchDescriptor<RelationshipEntity>(predicate: #Predicate { $0.id == relationshipID })
        if let existing = try ctx.fetch(descriptor).first {
            existing.inviteCode = newCode
            try ctx.save()
        }
    }

    func revokeInvite(code: String) async throws {
        try await remote.revokeInvite(code: code)
    }

    func invite(forCode code: String) async throws -> RelationshipInvite? {
        // Invites point at relationships the user is not part of yet, so there is nothing
        // useful to cache — go straight to the remote.
        try await remote.invite(forCode: code)
    }

    private func fetchLocal(for userID: String) throws -> [Relationship] {
        let ctx = context
        let descriptor = FetchDescriptor<RelationshipEntity>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try ctx.fetch(descriptor)
            .filter { $0.participantIDs.contains(userID) }
            .compactMap { $0.toModel() }
    }

    private func merge(relationships: [Relationship]) throws {
        let ctx = context
        for relationship in relationships {
            let descriptor = FetchDescriptor<RelationshipEntity>(predicate: #Predicate { $0.id == relationship.id })
            if let existing = try ctx.fetch(descriptor).first {
                existing.update(from: relationship)
            } else {
                ctx.insert(RelationshipEntity(from: relationship))
            }
        }
        try ctx.save()
    }
}
