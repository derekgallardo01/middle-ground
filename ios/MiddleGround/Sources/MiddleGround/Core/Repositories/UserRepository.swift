import Foundation

protocol UserRepository: Sendable {
    func currentUser() async throws -> User?
    func saveUser(_ user: User) async throws
    func user(id: String) async throws -> User?
}

actor MockUserRepository: UserRepository {
    private var users: [String: User] = [
        User.preview.id: .preview,
        User.preview2.id: .preview2
    ]
    
    private var currentUserID: String? = User.preview.id
    
    func currentUser() async throws -> User? {
        guard let currentUserID else { return nil }
        return users[currentUserID]
    }
    
    func saveUser(_ user: User) async throws {
        users[user.id] = user
        currentUserID = user.id
    }
    
    func user(id: String) async throws -> User? {
        users[id]
    }
}
