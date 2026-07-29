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
        // Return local data immediately, then refresh from remote
        let local = try fetchLocal()
        
        Task {
            do {
                let remoteRequests = try await remote.fetchRequests(for: userID)
                try await merge(requests: remoteRequests)
            } catch {
                // Offline: keep local data
            }
        }
        
        return local
    }
    
    func createRequest(_ request: Request) async throws {
        try await insertLocal(request, needsSync: true)
        try await remote.createRequest(request)
        try await markSynced(id: request.id)
    }
    
    func updateRequest(_ request: Request) async throws {
        try await insertLocal(request, needsSync: true)
        try await remote.updateRequest(request)
        try await markSynced(id: request.id)
    }
    
    func deleteRequest(_ request: Request) async throws {
        try await deleteLocal(id: request.id)
        try await remote.deleteRequest(request)
    }
    
    func observeRequests(for userID: String) -> AsyncStream<[Request]> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    // Initial local data
                    let local = try fetchLocal()
                    continuation.yield(local)
                    
                    // Then listen to remote updates
                    for await requests in await remote.observeRequests(for: userID) {
                        try await merge(requests: requests)
                        continuation.yield(try fetchLocal())
                    }
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
        let descriptor = FetchDescriptor<RequestEntity>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try modelContext.fetch(descriptor).compactMap { $0.toModel() }
    }
    
    private func merge(requests: [Request]) throws {
        for request in requests {
            let descriptor = FetchDescriptor<RequestEntity>(predicate: #Predicate { $0.id == request.id })
            if let existing = try modelContext.fetch(descriptor).first {
                // Only update if remote is newer
                if existing.updatedAt < request.updatedAt {
                    existing.update(from: request)
                    existing.needsSync = false
                }
            } else {
                modelContext.insert(RequestEntity(from: request))
            }
        }
        try modelContext.save()
    }
    
    private func insertLocal(_ request: Request, needsSync: Bool) throws {
        let descriptor = FetchDescriptor<RequestEntity>(predicate: #Predicate { $0.id == request.id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: request)
            existing.needsSync = needsSync
        } else {
            let entity = RequestEntity(from: request)
            entity.needsSync = needsSync
            modelContext.insert(entity)
        }
        try modelContext.save()
    }
    
    private func markSynced(id: String) throws {
        let descriptor = FetchDescriptor<RequestEntity>(predicate: #Predicate { $0.id == id })
        if let entity = try modelContext.fetch(descriptor).first {
            entity.needsSync = false
            try modelContext.save()
        }
    }
    
    private func deleteLocal(id: String) throws {
        let descriptor = FetchDescriptor<RequestEntity>(predicate: #Predicate { $0.id == id })
        if let entity = try modelContext.fetch(descriptor).first {
            modelContext.delete(entity)
            try modelContext.save()
        }
    }
}
