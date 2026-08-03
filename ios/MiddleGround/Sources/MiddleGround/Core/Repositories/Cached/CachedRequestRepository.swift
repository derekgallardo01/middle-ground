import Foundation
import SwiftData

actor CachedRequestRepository: RequestRepository {
    private let remote: RequestRepository
    private let modelContainer: ModelContainer

    init(remote: RequestRepository, modelContainer: ModelContainer) {
        self.remote = remote
        self.modelContainer = modelContainer
    }

    private var context: ModelContext {
        ModelContext(modelContainer)
    }

    func fetchRequests(for userID: String) async throws -> [Request] {
        // Refresh from remote and merge before returning, so callers never see a stale snapshot.
        // If the network is unavailable, fall through to whatever is cached locally.
        do {
            let remoteRequests = try await remote.fetchRequests(for: userID)
            try merge(requests: remoteRequests)
        } catch {
            // Offline: keep local data
        }

        return try fetchLocal(for: userID)
    }

    func createRequest(_ request: Request) async throws {
        try insertLocal(request, needsSync: true)
        try await remote.createRequest(request)
        try markSynced(id: request.id)
    }

    func updateRequest(_ request: Request) async throws {
        try insertLocal(request, needsSync: true)
        try await remote.updateRequest(request)
        try markSynced(id: request.id)
    }

    /// Remote first, then cache what came back.
    ///
    /// The opposite order to `updateRequest`, and deliberately: the appended chain is decided by
    /// the server inside a transaction, so there is nothing correct to write locally until it
    /// returns. Guessing the result here would put a message in the cache that may have lost a
    /// race — the exact failure the transaction exists to prevent.
    func appendMessage(
        _ message: NegotiationMessage,
        to requestID: String,
        proposedTime: Date?
    ) async throws -> Request {
        let updated = try await remote.appendMessage(
            message, to: requestID, proposedTime: proposedTime
        )
        try? insertLocal(updated, needsSync: false)
        return updated
    }

    func deleteRequest(_ request: Request) async throws {
        try deleteLocal(id: request.id)
        try await remote.deleteRequest(request)
    }

    // Invites and membership are server-side concerns: there is nothing useful to cache, and
    // a stale local copy of who can see a plan would be worse than none.
    func publishPlanInvite(code: String, requestID: String, ownerID: String) async throws {
        try await remote.publishPlanInvite(code: code, requestID: requestID, ownerID: ownerID)
    }

    func planInvite(forCode code: String) async throws -> String? {
        try await remote.planInvite(forCode: code)
    }

    func addParticipant(_ userID: String, to requestID: String) async throws {
        try await remote.addParticipant(userID, to: requestID)
    }

    nonisolated func observeRequests(for userID: String) -> AsyncStream<[Request]> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    // Initial local data
                    continuation.yield(try await self.fetchLocal(for: userID))

                    // Then listen to remote updates
                    for await requests in self.remote.observeRequests(for: userID) {
                        try await self.merge(requests: requests)
                        continuation.yield(try await self.fetchLocal(for: userID))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private

    /// Local requests **for a specific user**.
    ///
    /// This used to return every cached row regardless of owner, and `merge` never deletes, so
    /// signing out and signing in as someone else on the same device surfaced the previous
    /// user's requests. `CachedRelationshipRepository` already filtered correctly; this did not.
    private func fetchLocal(for userID: String) throws -> [Request] {
        let ctx = context
        let descriptor = FetchDescriptor<RequestEntity>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try ctx.fetch(descriptor)
            .compactMap { $0.toModel() }
            .filter { $0.allParticipantIDs.contains(userID) }
    }

    private func merge(requests: [Request]) throws {
        let ctx = context
        for request in requests {
            let descriptor = FetchDescriptor<RequestEntity>(predicate: #Predicate { $0.id == request.id })
            if let existing = try ctx.fetch(descriptor).first {
                // Only update if remote is newer
                if existing.updatedAt < request.updatedAt {
                    existing.update(from: request)
                    existing.needsSync = false
                }
            } else {
                ctx.insert(RequestEntity(from: request))
            }
        }
        try ctx.save()
    }

    private func insertLocal(_ request: Request, needsSync: Bool) throws {
        let ctx = context
        let descriptor = FetchDescriptor<RequestEntity>(predicate: #Predicate { $0.id == request.id })
        if let existing = try ctx.fetch(descriptor).first {
            existing.update(from: request)
            existing.needsSync = needsSync
        } else {
            let entity = RequestEntity(from: request)
            entity.needsSync = needsSync
            ctx.insert(entity)
        }
        try ctx.save()
    }

    private func markSynced(id: String) throws {
        let ctx = context
        let descriptor = FetchDescriptor<RequestEntity>(predicate: #Predicate { $0.id == id })
        if let entity = try ctx.fetch(descriptor).first {
            entity.needsSync = false
            try ctx.save()
        }
    }

    private func deleteLocal(id: String) throws {
        let ctx = context
        let descriptor = FetchDescriptor<RequestEntity>(predicate: #Predicate { $0.id == id })
        if let entity = try ctx.fetch(descriptor).first {
            ctx.delete(entity)
            try ctx.save()
        }
    }
}
