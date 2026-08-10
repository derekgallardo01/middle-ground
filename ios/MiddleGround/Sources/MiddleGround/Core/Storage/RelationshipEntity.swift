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
    /// How many people the group holds.
    ///
    /// The third field to be caught by this: `name` was dropped in `9ff2d97` and this one survived
    /// that fix. Absent from the entity, `toModel()` omitted the argument and `Relationship.init`
    /// fell back to `type.seatLimit` — so a friends group created with 2 seats read back as 8 and
    /// `hasRoom` said there was room for six more people who could never be admitted, because the
    /// server still enforces the real number.
    ///
    /// Optional and appended, so SwiftData migrates existing stores on its own. `nil` keeps
    /// meaning two, exactly as `seatCount` does.
    var seats: Int?
    var needsSync: Bool

    init(from relationship: Relationship) {
        self.id = relationship.id
        self.participantIDs = relationship.participantIDs
        self.name = relationship.name
        self.typeRaw = relationship.type.rawValue
        self.createdAt = relationship.createdAt
        self.growthScore = relationship.growthScore
        self.inviteCode = relationship.inviteCode
        self.seats = relationship.seats
        self.needsSync = false
    }

    func update(from relationship: Relationship) {
        self.participantIDs = relationship.participantIDs
        self.name = relationship.name
        self.typeRaw = relationship.type.rawValue
        self.createdAt = relationship.createdAt
        self.growthScore = relationship.growthScore
        self.inviteCode = relationship.inviteCode
        self.seats = relationship.seats
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
            inviteCode: inviteCode,
            // `?? 2`, matching `RelationshipDTO.toModel()` — not `seats` straight through.
            // `Relationship.init` reads a nil as "use the type's limit", which is right when
            // creating a group and wrong when loading one: a legacy row with no seats would come
            // back as eight while the server still enforced two (`data.get('seats', 2)`).
            seats: seats ?? 2
        )
    }
}
