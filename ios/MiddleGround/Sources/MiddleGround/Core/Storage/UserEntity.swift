import Foundation
import SwiftData

@Model
final class UserEntity {
    @Attribute(.unique) var id: String
    var name: String
    var avatarURLString: String?
    var createdAt: Date
    var needsSync: Bool

    init(from user: User) {
        self.id = user.id
        self.name = user.name
        self.avatarURLString = user.avatarURL?.absoluteString
        self.createdAt = user.createdAt
        self.needsSync = false
    }

    func update(from user: User) {
        self.name = user.name
        self.avatarURLString = user.avatarURL?.absoluteString
        self.createdAt = user.createdAt
    }

    func toModel() -> User {
        User(
            id: id,
            name: name,
            avatarURL: avatarURLString.flatMap { URL(string: $0) },
            createdAt: createdAt
        )
    }
}
