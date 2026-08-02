#if DEBUG
import Foundation
import os

/// Auth stand-in for Xcode previews and mock mode, where Firebase is not configured.
///
/// `AuthService.init` reaches for `Auth.auth()`, which traps without `FirebaseApp.configure()`.
/// Registering this instead is what makes `AppConfiguration.useMockRepositories` actually usable.
///
/// The signed-in user is `User.preview` on purpose: its `id` is a participant of
/// `Relationship.preview`, so partner lookup in `CreateRequestViewModel` resolves.
actor PreviewAuthService: AuthServiceProtocol {
    private var user: User? {
        // Read out to a local first: the lock's closure is @Sendable and so cannot touch
        // actor-isolated state directly.
        didSet {
            let id = user?.id
            lastKnownID.withLock { $0 = id }
        }
    }

    /// Mirrors `user.id` so `currentUserID` can be read without awaiting the actor, matching the
    /// real service where the ID comes straight off the in-memory Firebase session.
    ///
    /// A `let` of a Sendable type, so the actor lets it be read from outside. `Mutex` would be
    /// the modern choice but it needs iOS 18 and this app supports 17.
    private let lastKnownID = OSAllocatedUnfairLock<String?>(initialState: nil)

    nonisolated var currentUserID: String? { lastKnownID.withLock { $0 } }

    init(user: User? = .preview) {
        self.user = user
        let id = user?.id
        lastKnownID.withLock { $0 = id }
    }

    func currentUser() async -> User? {
        user
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws -> User {
        let signedIn = user ?? .preview
        user = signedIn
        return signedIn
    }

    func signOut() async throws {
        user = nil
    }

    /// Previews and mock mode are never admin: the panel must not appear by accident.
    func isAdmin() async -> Bool { false }

    func deleteAccount(appleAuthorizationCode: String?) async throws {
        user = nil
    }

    func signInAsTestUser(named name: String) async throws -> User {
        let signedIn = User(id: "preview_\(name)", name: name)
        user = signedIn
        return signedIn
    }

    nonisolated func authStateStream() -> AsyncStream<User?> {
        AsyncStream { continuation in
            Task {
                continuation.yield(await self.user)
                continuation.finish()
            }
        }
    }
}
#endif
