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

        return try fetchLocal()
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

    func deleteRequest(_ request: Request) async throws {
        try deleteLocal(id: request.id)
        try await remote.deleteRequest(request)
    }

    nonisolated func observeRequests(for userID: String) -> AsyncStream<[Request]> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    // Initial local data
                    continuation.yield(try await self.fetchLocal())

                    // Then listen to remote updates
                    for await requests in self.remote.observeRequests(for: userID) {
                        try await self.merge(requests: requests)
                        continuation.yield(try await self.fetchLocal())
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

    private func fetchLocal() throws -> [Request] {
        let ctx = context
        let descriptor = FetchDescriptor<RequestEntity>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try ctx.fetch(descriptor).compactMap { $0.toModel() }
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
