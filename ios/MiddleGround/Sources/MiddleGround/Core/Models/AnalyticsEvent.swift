import Foundation

/// A recorded product-usage event.
///
/// Events are written by the client for the signed-in user only (enforced in `firestore.rules`)
/// and are readable solely by an admin. They exist so the admin panel can answer questions the
/// raw documents cannot — funnels, retention, and what happened in what order.
///
/// Recording these is disclosed in the Privacy Policy. If you add a type, add it there too.
struct AnalyticsEvent: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let userID: String
    let type: EventType
    let requestID: String?
    let relationshipID: String?
    /// Small, non-sensitive extras (a response type, a category). Never free text a user typed.
    let metadata: [String: String]
    let at: Date

    init(
        id: String = UUID().uuidString,
        userID: String,
        type: EventType,
        requestID: String? = nil,
        relationshipID: String? = nil,
        metadata: [String: String] = [:],
        at: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.type = type
        self.requestID = requestID
        self.relationshipID = relationshipID
        self.metadata = metadata
        self.at = at
    }
}

enum EventType: String, Codable, CaseIterable, Identifiable, Sendable {
    case signedUp = "signed_up"
    case onboardingCompleted = "onboarding_completed"
    case relationshipCreated = "relationship_created"
    case relationshipLeft = "relationship_left"
    case inviteRedeemed = "invite_redeemed"
    case contentReported = "content_reported"
    case requestCreated = "request_created"
    case requestResponded = "request_responded"
    case requestCancelled = "request_cancelled"
    /// Someone said whether an accepted plan actually happened.
    case requestConfirmed = "request_confirmed"
    case appOpened = "app_opened"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .signedUp: return "Signed up"
        case .onboardingCompleted: return "Finished onboarding"
        case .relationshipCreated: return "Created a group"
        case .relationshipLeft: return "Left a group"
        case .inviteRedeemed: return "Redeemed an invite"
        case .contentReported: return "Reported content"
        case .requestCreated: return "Created a request"
        case .requestResponded: return "Responded"
        case .requestCancelled: return "Cancelled a request"
        case .requestConfirmed: return "Confirmed a plan"
        case .appOpened: return "Opened the app"
        }
    }

    var iconName: String {
        switch self {
        case .signedUp: return "person.badge.plus"
        case .onboardingCompleted: return "checkmark.seal"
        case .relationshipCreated: return "person.2.badge.plus"
        case .relationshipLeft: return "person.2.slash"
        case .inviteRedeemed: return "ticket"
        case .contentReported: return "flag"
        case .requestCreated: return "square.and.pencil"
        case .requestResponded: return "arrowshape.turn.up.left"
        case .requestCancelled: return "xmark.circle"
        case .requestConfirmed: return "checkmark.circle"
        case .appOpened: return "iphone"
        }
    }
}
