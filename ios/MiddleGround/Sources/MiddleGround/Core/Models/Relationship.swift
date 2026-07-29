import Foundation

enum RelationshipType: String, Codable, CaseIterable, Identifiable {
    case couple
    case family
    case friends
    case roommates
    case coworkers
    case parents
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .couple: return "Couple"
        case .family: return "Family"
        case .friends: return "Friends"
        case .roommates: return "Roommates"
        case .coworkers: return "Coworkers"
        case .parents: return "Parents"
        }
    }
    
    var iconName: String {
        switch self {
        case .couple: return "heart.fill"
        case .family: return "house.fill"
        case .friends: return "person.2.fill"
        case .roommates: return "bed.double.fill"
        case .coworkers: return "briefcase.fill"
        case .parents: return "figure.and.child.holdinghands"
        }
    }
}

struct Relationship: Identifiable, Hashable, Codable {
    let id: String
    var participantIDs: [String]
    var type: RelationshipType
    var createdAt: Date
    var growthScore: Int
    
    init(id: String, participantIDs: [String], type: RelationshipType, createdAt: Date = Date(), growthScore: Int = 0) {
        self.id = id
        self.participantIDs = participantIDs
        self.type = type
        self.createdAt = createdAt
        self.growthScore = growthScore
    }
}

extension Relationship {
    static let preview = Relationship(
        id: "rel_1",
        participantIDs: [User.preview.id, User.preview2.id],
        type: .couple,
        growthScore: 85
    )
}
