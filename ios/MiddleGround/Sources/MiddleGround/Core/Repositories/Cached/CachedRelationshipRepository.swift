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
    
    func fetchRelationships(for userID: String) async throws -> [Relationship] {
        let remoteRelationships = try await remote.fetchRelationships(for: userID)
        try await merge(relationships: remoteRelationships)
        return try fetchLocal(for: userID)
    }
    
    func saveRelationship(_ relationship: Relationship) async throws {
        try await remote.saveRelationship(relationship)
        try await merge(relationships: [relationship])
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
