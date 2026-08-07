import Foundation
import SwiftData

@Model
final class RelationshipEntity {
    @Attribute(.unique) var id: String
    var participantIDs: [String]
    /// What the group is called. Cached because it is *read* from here — this repository is
    /// remote-then-local, so a name that is not persisted is a name every group loses. "Sunday
    /// hikers" came back nameless and was then labelled with one member's name.
    ///
    /// Optional, and appended, so SwiftData migrates existing stores automatically.
    var name: String?
    var typeRaw: String
    var createdAt: Date
    var growthScore: Int
    var inviteCode: String
    var needsSync: Bool

    init(from relationship: Relationship) {
        self.id = relationship.id
        self.participantIDs = relationship.participantIDs
        self.name = relationship.name
        self.typeRaw = relationship.type.rawValue
        self.createdAt = relationship.createdAt
        self.growthScore = relationship.growthScore
        self.inviteCode = relationship.inviteCode
        self.needsSync = false
    }

    func update(from relationship: Relationship) {
        self.participantIDs = relationship.participantIDs
        self.name = relationship.name
        self.typeRaw = relationship.type.rawValue
        self.createdAt = relationship.createdAt
        self.growthScore = relationship.growthScore
        self.inviteCode = relationship.inviteCode
    }

    func toModel() -> Relationship? {
        guard let type = RelationshipType(rawValue: typeRaw) else { return nil }
        return Relationship(
            id: id,
            participantIDs: participantIDs,
            type: type,
            createdAt: createdAt,
            growthScore: growthScore,
            name: name,
            inviteCode: inviteCode
        )
    }
}
