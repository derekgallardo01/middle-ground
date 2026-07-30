import Foundation
import SwiftData

actor CachedUserRepository: UserRepository {
    private let remote: UserRepository
    private let modelContainer: ModelContainer

    init(remote: UserRepository, modelContainer: ModelContainer) {
        self.remote = remote
        self.modelContainer = modelContainer
    }

    private var context: ModelContext {
        ModelContext(modelContainer)
    }

    func currentUser() async throws -> User? {
        if let remoteUser = try await remote.currentUser() {
            try saveLocal(remoteUser)
            return remoteUser
        }
        return try fetchLocal(id: "current")
    }

    func saveUser(_ user: User) async throws {
        try await remote.saveUser(user)
        try saveLocal(user)
    }

    func user(id: String) async throws -> User? {
        if let remoteUser = try await remote.user(id: id) {
            try saveLocal(remoteUser)
            return remoteUser
        }
        return try fetchLocal(id: id)
    }

    private func fetchLocal(id: String) throws -> User? {
        let ctx = context
        let descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.id == id })
        return try ctx.fetch(descriptor).first?.toModel()
    }

    private func saveLocal(_ user: User) throws {
        let ctx = context
        let descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.id == user.id })
        if let existing = try ctx.fetch(descriptor).first {
            existing.update(from: user)
        } else {
            ctx.insert(UserEntity(from: user))
        }
        try ctx.save()
    }
}
