import Foundation

protocol UserRepository: Sendable {
    func currentUser() async throws -> User?
    func saveUser(_ user: User) async throws
    func user(id: String) async throws -> User?
}

actor MockUserRepository: UserRepository {
    /// Everyone who appears on a fixture, Priya included.
    ///
    /// She was missing while she was on the three-person plan, so anything resolving a name for
    /// her fell back to "Someone" — most visibly in the report picker, where choosing between
    /// "Sam" and "Someone" is no choice at all on a safety-critical screen.
    private var users: [String: User] = [
        User.preview.id: .preview,
        User.preview2.id: .preview2,
        User.preview3.id: .preview3
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
