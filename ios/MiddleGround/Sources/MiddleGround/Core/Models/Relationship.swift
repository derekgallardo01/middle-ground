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

    /// Short human-shareable code a second person enters to join this relationship.
    var inviteCode: String

    init(
        id: String,
        participantIDs: [String],
        type: RelationshipType,
        createdAt: Date = Date(),
        growthScore: Int = 0,
        inviteCode: String = Relationship.generateInviteCode()
    ) {
        self.id = id
        self.participantIDs = participantIDs
        self.type = type
        self.createdAt = createdAt
        self.growthScore = growthScore
        self.inviteCode = inviteCode
    }

    /// True once a second person has joined — until then no requests can be sent.
    var isPaired: Bool { participantIDs.count > 1 }

    /// The other participant, from the perspective of `userID`.
    func partnerID(excluding userID: String) -> String? {
        participantIDs.first { $0 != userID }
    }
}

extension Relationship {
    /// Ambiguous characters (0/O, 1/I/L) are excluded so codes can be read aloud.
    private static let inviteCodeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    static func generateInviteCode(length: Int = 6) -> String {
        String((0..<length).compactMap { _ in inviteCodeAlphabet.randomElement() })
    }

    /// Normalises user input so "abc-123" and "ABC123" match the same code.
    static func normalizeInviteCode(_ raw: String) -> String {
        raw.uppercased().filter { inviteCodeAlphabet.contains($0) }
    }
}

extension Relationship {
    static let preview = Relationship(
        id: "rel_1",
        participantIDs: [User.preview.id, User.preview2.id],
        type: .couple,
        growthScore: 85,
        inviteCode: "MG24KT"
    )
}
