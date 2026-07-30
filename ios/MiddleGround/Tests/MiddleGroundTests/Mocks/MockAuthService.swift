import Foundation
@testable import MiddleGround

actor MockAuthService: AuthServiceProtocol {
    var mockUser: User?
    var shouldThrowOnSignOut = false

    init(mockUser: User? = .preview) {
        self.mockUser = mockUser
    }

    func currentUser() async -> User? {
        mockUser
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws -> User {
        mockUser ?? User(id: "apple_user", name: "Apple User")
    }

    func signOut() async throws {
        if shouldThrowOnSignOut {
            throw AuthError.notAuthenticated
        }
        mockUser = nil
    }

    private(set) var deleteAccountCalled = false

    func deleteAccount(appleAuthorizationCode: String?) async throws {
        if shouldThrowOnSignOut { throw AuthError.notAuthenticated }
        deleteAccountCalled = true
        mockUser = nil
    }

    func signInAsTestUser(named name: String) async throws -> User {
        let signedIn = User(id: "test_\(name)", name: name)
        mockUser = signedIn
        return signedIn
    }

    nonisolated func authStateStream() -> AsyncStream<User?> {
        AsyncStream { continuation in
            Task {
                continuation.yield(await self.mockUser)
                continuation.finish()
            }
        }
    }
}
