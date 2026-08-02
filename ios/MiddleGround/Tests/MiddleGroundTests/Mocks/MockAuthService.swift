import Foundation
import os
@testable import MiddleGround

actor MockAuthService: AuthServiceProtocol {
    var mockUser: User? {
        // Read out to a local first: the lock's closure is @Sendable and so cannot touch
        // actor-isolated state directly.
        didSet {
            let id = mockUser?.id
            lastKnownID.withLock { $0 = id }
        }
    }
    var shouldThrowOnSignOut = false

    /// Mirrors `mockUser.id` so `currentUserID` is readable without awaiting the actor, the same
    /// way the real service reads it off the in-memory Firebase session.
    private let lastKnownID = OSAllocatedUnfairLock<String?>(initialState: nil)

    nonisolated var currentUserID: String? { lastKnownID.withLock { $0 } }

    init(mockUser: User? = .preview) {
        self.mockUser = mockUser
        let id = mockUser?.id
        lastKnownID.withLock { $0 = id }
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

    /// Overridable so a test can exercise the admin path without a real token.
    var mockIsAdmin = false

    func isAdmin() async -> Bool { mockIsAdmin }

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
