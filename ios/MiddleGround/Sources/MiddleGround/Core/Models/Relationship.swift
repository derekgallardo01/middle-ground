import Foundation

enum RelationshipType: String, Codable, CaseIterable, Identifiable {
    case couple
    case family
    case friends
    case roommates
    case coworkers
    case parents

    var id: String { rawValue }

    /// The kind of request this sort of group usually means.
    ///
    /// Compose opened every plan as **Relationship**, whoever it was addressed to, so a night out
    /// with the hiking group was filed as a relationship request — visible on the sheet, and
    /// carried into `plan_outcomes`, where the category is the only thing distinguishing one kind
    /// of plan from another.
    ///
    /// A suggestion, not a rule: it seeds the picker and any tap on it wins.
    var suggestedRequestCategory: RequestCategory {
        switch self {
        case .couple: return .relationship
        case .family, .parents: return .family
        case .friends, .coworkers: return .friends
        // Not "friends": what roommates plan together is mostly the running of a house, which is
        // what Daily Life is for.
        case .roommates: return .daily
        }
    }

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

    /// How many people this kind of group can hold.
    ///
    /// A couple is two by definition — not a default, a constraint, and the reason the reliability
    /// score and the leaderboard both exclude couples is that a ranking between two partners is a
    /// weapon rather than a signal. Letting a "couple" hold three would quietly reopen that.
    ///
    /// Everything else holds eight. The number is arbitrary but the ceiling is not: an unbounded
    /// group is a mailing list, and every request fans out to everyone in it.
    var seatLimit: Int {
        switch self {
        case .couple: return 2
        default: return 8
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

    /// What the members call this group.
    ///
    /// Optional because groups were previously identified only by `type`, which is fine for one
    /// group and useless for two — "Friends" and "Friends" are indistinguishable in a picker.
    /// Existing documents have no name and must keep decoding.
    var name: String?

    /// Short human-shareable code someone enters to join this relationship.
    var inviteCode: String

    /// How many people this group may hold in total.
    ///
    /// Stored rather than derived from `type` so the ceiling a group was created under cannot be
    /// changed by editing its type later, and so the rules can enforce it without a second read.
    /// Optional because every group that predates this has no such field: `seats` treats absence
    /// as two, which is exactly the behaviour those groups already had.
    var seats: Int?

    init(
        id: String,
        participantIDs: [String],
        type: RelationshipType,
        createdAt: Date = Date(),
        growthScore: Int = 0,
        name: String? = nil,
        inviteCode: String = Relationship.generateInviteCode(),
        seats: Int? = nil
    ) {
        self.id = id
        self.participantIDs = participantIDs
        self.type = type
        self.createdAt = createdAt
        self.growthScore = growthScore
        self.name = name
        self.inviteCode = inviteCode
        self.seats = seats ?? type.seatLimit
    }

    /// What to call this group when the partner's name is not the right label — a named group, or
    /// the type as a last resort. `RelationshipService.displayLabels` prefers a partner's name for
    /// two-person groups; this is the fallback chain behind it.
    var label: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return type.displayName
    }

    /// True once a second person has joined — until then no requests can be sent.
    var isPaired: Bool { participantIDs.count > 1 }

    /// The ceiling, treating a missing value as two.
    ///
    /// Absence means two on purpose. Every group written before seats existed could hold exactly
    /// two people, and reading absence as "unlimited" would silently widen every one of them.
    var seatCount: Int { seats ?? 2 }

    var hasRoom: Bool { participantIDs.count < seatCount }

    /// Everyone except the person asking.
    func otherIDs(excluding userID: String) -> [String] {
        participantIDs.filter { $0 != userID }
    }

    /// The other participant, from the perspective of `userID`.
    ///
    /// Only meaningful for a two-person group; with three it returns an arbitrary one of them.
    /// Callers that need everybody want `otherIDs(excluding:)`.
    func partnerID(excluding userID: String) -> String? {
        participantIDs.first { $0 != userID }
    }
}

/// What an invite code resolves to.
///
/// Deliberately does *not* embed the `Relationship`: security rules only let participants
/// read a relationship, so someone joining cannot fetch it before they are a member. The
/// invite document carries everything the join flow needs.
struct RelationshipInvite: Sendable, Equatable {
    let code: String
    let relationshipID: String
    let ownerID: String
}

extension Relationship {
    /// Ambiguous characters (0/O, 1/I/L) are excluded so codes can be read aloud.
    private static let inviteCodeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    /// Codes are exactly this long, which is what makes `==` the right check on input rather
    /// than `>=`. A floor accepted a pasted message body — the alphabet filter reduces it to a
    /// long run of letters — so the client waved it through and the server rejected it with a
    /// raw error in an alert titled "Oops".
    static let inviteCodeLength = 6

    static func generateInviteCode(length: Int = inviteCodeLength) -> String {
        String((0..<length).compactMap { _ in inviteCodeAlphabet.randomElement() })
    }

    /// The invite code carried by a universal link, if that is what this URL is.
    ///
    /// Deliberately strict. It accepts `https://seekmiddleground.com/join/MG24KT` and nothing
    /// else — not a bare path, not another host, not a longer trail of segments — because a URL
    /// that merely *looks* like an invite would silently drop somebody into a join they never
    /// asked for. Anything unrecognised returns nil and the link opens the web page instead,
    /// which is the safe direction to fail.
    static func inviteCode(fromLink url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host == "seekmiddleground.com" else { return nil }

        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0] == "join" else { return nil }

        let code = normalizeInviteCode(String(parts[1]))
        return code.count == inviteCodeLength ? code : nil
    }

    /// Normalises user input so "abc-123" and "ABC123" match the same code.
    static func normalizeInviteCode(_ raw: String) -> String {
        raw.uppercased().filter { inviteCodeAlphabet.contains($0) }
    }
}

extension Array where Element == Relationship {
    /// True when there are groups but nobody has joined any of them.
    ///
    /// The distinction that matters: having no groups is a person who has not started, and
    /// having only unpaired ones is a person who is waiting. Both leave the app inert, and both
    /// need the same thing — somebody to accept the invite.
    ///
    /// Defined once because it was written out twice, in CreateRequestViewModel and
    /// SpontaneousRequestViewModel, and a rule duplicated verbatim is a rule that drifts.
    var awaitingSomebody: Bool {
        !isEmpty && allSatisfy { !$0.isPaired }
    }

    /// Nothing to plan with: no groups at all, or none anybody has joined.
    var hasNobodyToPlanWith: Bool { isEmpty || awaitingSomebody }
}

extension Relationship {
    static let preview = Relationship(
        id: "rel_1",
        participantIDs: [User.preview.id, User.preview2.id],
        type: .couple,
        growthScore: 85,
        inviteCode: "MG24KT"
    )

    /// Three people, with a seat still free — the state a pair cannot demonstrate.
    static let previewGroup = Relationship(
        id: "rel_2",
        participantIDs: [User.preview.id, User.preview2.id, User.preview3.id],
        type: .friends,
        growthScore: 40,
        name: "Sunday hikers",
        inviteCode: "MG7QP2"
    )
}
