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

/// What a goal counts towards.
///
/// Progress used to be resolved by switching on hardcoded achievement IDs, with
/// `default: progress = 0` — so any goal added without also editing that switch would sit at
/// zero forever and never unlock, silently. Naming the metric on the goal itself makes adding
/// one a line of data rather than a line of data plus a line of logic that is easy to forget.
enum GoalMetric: String, Codable, Hashable, Sendable {
    case negotiated
    case accepted
    case weekendAccepted
    case streakDays
    /// XP within `Achievement.category` — the per-activity goals.
    case categoryXP
}

struct Achievement: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let description: String
    let iconName: String
    let requiredValue: Int
    var unlockedAt: Date?

    /// What this goal measures. Defaults per legacy ID when decoding older stored blobs.
    var metric: GoalMetric
    /// Scopes `categoryXP` goals; nil for everything else.
    var category: RequestCategory?

    var isUnlocked: Bool { unlockedAt != nil }

    init(
        id: String,
        title: String,
        description: String,
        iconName: String,
        requiredValue: Int,
        unlockedAt: Date? = nil,
        metric: GoalMetric = .negotiated,
        category: RequestCategory? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.iconName = iconName
        self.requiredValue = requiredValue
        self.unlockedAt = unlockedAt
        self.metric = metric
        self.category = category
    }

    /// Tolerates achievements stored before goals carried their own metric.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        iconName = try container.decode(String.self, forKey: .iconName)
        requiredValue = try container.decode(Int.self, forKey: .requiredValue)
        unlockedAt = try container.decodeIfPresent(Date.self, forKey: .unlockedAt)
        category = try container.decodeIfPresent(RequestCategory.self, forKey: .category)
        metric = try container.decodeIfPresent(GoalMetric.self, forKey: .metric)
            ?? Achievement.legacyMetric(forID: id)
    }

    /// The mapping the old switch encoded, preserved so achievements already on someone's device
    /// keep measuring the same thing.
    private static func legacyMetric(forID id: String) -> GoalMetric {
        switch id {
        case "ach_2": return .weekendAccepted
        case "ach_3": return .streakDays
        default: return .negotiated
        }
    }

    /// How far along this goal is, given the user's stats.
    func progress(in stats: GamificationStats) -> Int {
        switch metric {
        case .negotiated: return stats.negotiatedCount
        case .accepted: return stats.acceptedCount
        case .weekendAccepted: return stats.weekendAcceptedCount
        case .streakDays: return stats.streakDays
        case .categoryXP:
            guard let category else { return 0 }
            return stats.categoryXP[category.rawValue] ?? 0
        }
    }
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
