import Foundation
import FirebaseAuth
import Factory

enum AuthError: Error, Equatable {
    case notAuthenticated
    case invalidCredential
    case firebaseError(String)
}

protocol AuthServiceProtocol: Sendable {
    func currentUser() async -> User?
    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws -> User
    func signOut() async throws
    func authStateStream() -> AsyncStream<User?>
}

actor AuthService: AuthServiceProtocol {
    private let userRepository = Container.shared.remoteUserRepository()

    func currentUser() async -> User? {
        guard let firebaseUser = Auth.auth().currentUser else { return nil }
        return try? await fetchUser(id: firebaseUser.uid)
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws -> User {
        let credential = OAuthProvider.credential(
            providerID: .apple,
            idToken: idToken,
            rawNonce: nonce
        )

        do {
            let result = try await Auth.auth().signIn(with: credential)
            let firebaseUser = result.user

            let displayName = fullName?.formatted()
                ?? firebaseUser.displayName
                ?? "New User"

            let user = User(
                id: firebaseUser.uid,
                name: displayName,
                avatarURL: firebaseUser.photoURL
            )

            try await userRepository.saveUser(user)
            return user
        } catch {
            throw AuthError.firebaseError(error.localizedDescription)
        }
    }

    func signOut() async throws {
        do {
            try Auth.auth().signOut()
        } catch {
            throw AuthError.firebaseError(error.localizedDescription)
        }
    }

    /// Each stream owns its own Firebase listener and removes it when the stream terminates,
    /// so no auth-state is held as actor storage.
    nonisolated func authStateStream() -> AsyncStream<User?> {
        AsyncStream { continuation in
            let handle = Auth.auth().addStateDidChangeListener { _, firebaseUser in
                let uid = firebaseUser?.uid
                Task {
                    var user: User?
                    if let uid {
                        user = try? await self.fetchUser(id: uid)
                    }
                    continuation.yield(user)
                }
            }
            continuation.onTermination = { _ in
                Auth.auth().removeStateDidChangeListener(handle)
            }
        }
    }

    private func fetchUser(id: String) async throws -> User? {
        try await userRepository.user(id: id)
    }
}
