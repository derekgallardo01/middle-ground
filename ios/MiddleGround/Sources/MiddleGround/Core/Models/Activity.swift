import Foundation

enum ActivityType: String, Codable, Identifiable {
    case streakUpdate
    case xpEarned
    case achievementUnlocked
    case milestoneReached
    case moodLogged
    case memoryAdded

    var id: String { rawValue }
}

struct Activity: Identifiable, Hashable, Codable {
    let id: String
    let userID: String
    let type: ActivityType
    let title: String
    let subtitle: String?
    let value: Int
    let timestamp: Date

    init(id: String = UUID().uuidString,
         userID: String,
         type: ActivityType,
         title: String,
         subtitle: String? = nil,
         value: Int,
         timestamp: Date = Date()) {
        self.id = id
        self.userID = userID
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.timestamp = timestamp
    }
}

struct Achievement: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let description: String
    let iconName: String
    let requiredValue: Int
    var unlockedAt: Date?

    var isUnlocked: Bool { unlockedAt != nil }
}

extension Activity {
    static let preview = Activity(
        userID: User.preview.id,
        type: .streakUpdate,
        title: "12 day streak",
        subtitle: "Keep it going!",
        value: 12
    )
}

extension Achievement {
    static let preview = Achievement(
        id: "ach_1",
        title: "Great Communicator",
        description: "Resolved 10 requests through compromise",
        iconName: "trophy.fill",
        requiredValue: 10,
        unlockedAt: Date()
    )
}
