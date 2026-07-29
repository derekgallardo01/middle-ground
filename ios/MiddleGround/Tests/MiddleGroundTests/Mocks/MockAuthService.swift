import Foundation
@testable import MiddleGround

actor MockAuthService: AuthServiceProtocol {
    var mockUser: User?
    var shouldThrowOnSignOut = false
    
    init(mockUser: User? = User(id: "test_user", name: "Test User")) {
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
    
    func authStateStream() -> AsyncStream<User?> {
        AsyncStream { continuation in
            continuation.yield(mockUser)
            continuation.finish()
        }
    }
}
