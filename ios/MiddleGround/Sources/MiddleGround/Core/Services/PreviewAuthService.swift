#if DEBUG
import Foundation

/// Auth stand-in for Xcode previews and mock mode, where Firebase is not configured.
///
/// `AuthService.init` reaches for `Auth.auth()`, which traps without `FirebaseApp.configure()`.
/// Registering this instead is what makes `AppConfiguration.useMockRepositories` actually usable.
///
/// The signed-in user is `User.preview` on purpose: its `id` is a participant of
/// `Relationship.preview`, so partner lookup in `CreateRequestViewModel` resolves.
actor PreviewAuthService: AuthServiceProtocol {
    private var user: User?

    init(user: User? = .preview) {
        self.user = user
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
