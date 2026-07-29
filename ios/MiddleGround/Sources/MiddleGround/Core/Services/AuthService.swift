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
    private var handle: AuthStateDidChangeListenerHandle?
    private var continuation: AsyncStream<User?>.Continuation?
    
    init() {
        self.handle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task {
                let user = firebaseUser != nil ? try? await self?.fetchUser(id: firebaseUser!.uid) : nil
                self?.continuation?.yield(user)
            }
        }
    }
    
    func currentUser() async -> User? {
        guard let firebaseUser = Auth.auth().currentUser else { return nil }
        return try? await fetchUser(id: firebaseUser.uid)
    }
    
    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws -> User {
        let credential = OAuthProvider.credential(
            withProviderID: "apple.com",
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
    
    func authStateStream() -> AsyncStream<User?> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.continuation = nil
            }
        }
    }
    
    private func fetchUser(id: String) async throws -> User? {
        try await userRepository.user(id: id)
    }
}
