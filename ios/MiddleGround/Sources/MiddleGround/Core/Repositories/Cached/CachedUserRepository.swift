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

    /// Remote first, cache as a fallback.
    ///
    /// The `try await` used to propagate, which made the local read below reachable only when the
    /// remote call *succeeded and returned nil* — the one case where the cache is least likely to
    /// help. Offline, it threw. See `user(id:)` for what that cost.
    func currentUser() async throws -> User? {
        do {
            if let remoteUser = try await remote.currentUser() {
                try saveLocal(remoteUser)
                return remoteUser
            }
        } catch {
            MGLog.storage.info("Reading the current user failed; falling back to the cache.")
        }
        return try fetchLocal(id: "current")
    }

    func saveUser(_ user: User) async throws {
        try await remote.saveUser(user)
        try saveLocal(user)
    }

    /// The read that decided whether somebody was signed in.
    ///
    /// `AuthService.currentUser()` wraps this in `try?`, `AppState.checkAuthState` sets
    /// `isOnboarded = currentUser != nil`, and the app renders onboarding when that is false. So
    /// an already-signed-in user with no connection saw the app appear and then get replaced by
    /// the sign-in wall — their account intact, their session intact, and nothing on screen
    /// saying the problem was the network. The cached profile answers this perfectly well.
    func user(id: String) async throws -> User? {
        do {
            if let remoteUser = try await remote.user(id: id) {
                try saveLocal(remoteUser)
                return remoteUser
            }
        } catch {
            MGLog.storage.info("Reading a user profile failed; falling back to the cache.")
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
