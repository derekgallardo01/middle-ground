import Foundation
import SwiftData

@Model
final class RelationshipEntity {
    @Attribute(.unique) var id: String
    var participantIDs: [String]
    var typeRaw: String
    var createdAt: Date
    var growthScore: Int
    var needsSync: Bool
    
    init(from relationship: Relationship) {
        self.id = relationship.id
        self.participantIDs = relationship.participantIDs
        self.typeRaw = relationship.type.rawValue
        self.createdAt = relationship.createdAt
        self.growthScore = relationship.growthScore
        self.needsSync = false
    }
    
    func update(from relationship: Relationship) {
        self.participantIDs = relationship.participantIDs
        self.typeRaw = relationship.type.rawValue
        self.createdAt = relationship.createdAt
        self.growthScore = relationship.growthScore
    }
    
    func toModel() -> Relationship? {
        guard let type = RelationshipType(rawValue: typeRaw) else { return nil }
        return Relationship(
            id: id,
            participantIDs: participantIDs,
            type: type,
            createdAt: createdAt,
            growthScore: growthScore
        )
    }
}
