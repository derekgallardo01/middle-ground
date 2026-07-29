import Foundation

struct User: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var avatarURL: URL?
    var createdAt: Date
    
    init(id: String, name: String, avatarURL: URL? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.createdAt = createdAt
    }
}

extension User {
    static let preview = User(id: "user_1", name: "Alex")
    static let preview2 = User(id: "user_2", name: "Sam")
}
