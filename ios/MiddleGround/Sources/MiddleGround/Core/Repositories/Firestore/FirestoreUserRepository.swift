import Foundation
import FirebaseAuth
import FirebaseFirestore

actor FirestoreUserRepository: UserRepository {
    private let db = Firestore.firestore()
    private let collection = "users"

    func currentUser() async throws -> User? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return try await user(id: uid)
    }

    func saveUser(_ user: User) async throws {
        let dto = UserDTO(from: user)
        try db.collection(collection).document(user.id).setData(from: dto, merge: true)
    }

    func user(id: String) async throws -> User? {
        let document = try await db.collection(collection).document(id).getDocument()
        return try? document.data(as: UserDTO.self).toModel()
    }
}
