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
    /// A code was minted for somebody to use — the denominator redemption had none.
    ///
    /// Without it there is no way to ask what share of invites turn into a paired user, because
    /// only the successes were ever recorded. `metadata["kind"]` matches `inviteRedeemed`.
    case inviteCreated = "invite_created"
    /// The share sheet was opened on an invite code.
    ///
    /// Named for what is actually observable. `ShareLink` reports nothing back, so this records
    /// somebody reaching for the share sheet, not a message arriving with anybody. It is the
    /// closest honest denominator: a code that was never shared cannot become a paired user, and
    /// counting group creations instead would count every code that was never sent.
    case inviteShared = "invite_shared"
    case inviteRedeemed = "invite_redeemed"
    case contentReported = "content_reported"
    case requestCreated = "request_created"
    case requestResponded = "request_responded"
    case requestCancelled = "request_cancelled"
    /// Someone said whether an accepted plan actually happened.
    case requestConfirmed = "request_confirmed"
    /// Someone said they are still coming to a plan that had gone quiet.
    ///
    /// Kept apart from `requestConfirmed`: that is about a plan that has happened, this is about
    /// one that still might. Folding them together would make the follow-through figure count
    /// intentions as attendance.
    case requestStillOn = "request_still_on"
    case appOpened = "app_opened"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .signedUp: return "Signed up"
        case .onboardingCompleted: return "Finished onboarding"
        case .relationshipCreated: return "Created a group"
        case .relationshipLeft: return "Left a group"
        case .inviteCreated: return "Made an invite"
        case .inviteShared: return "Opened the share sheet"
        case .inviteRedeemed: return "Redeemed an invite"
        case .contentReported: return "Reported content"
        case .requestCreated: return "Created a request"
        case .requestResponded: return "Responded"
        case .requestCancelled: return "Cancelled a request"
        case .requestConfirmed: return "Confirmed a plan"
        case .requestStillOn: return "Said still on"
        case .appOpened: return "Opened the app"
        }
    }

    var iconName: String {
        switch self {
        case .signedUp: return "person.badge.plus"
        case .onboardingCompleted: return "checkmark.seal"
        case .relationshipCreated: return "person.2.badge.plus"
        case .relationshipLeft: return "person.2.slash"
        case .inviteCreated: return "ticket.fill"
        case .inviteShared: return "square.and.arrow.up"
        case .inviteRedeemed: return "ticket"
        case .contentReported: return "flag"
        case .requestCreated: return "square.and.pencil"
        case .requestResponded: return "arrowshape.turn.up.left"
        case .requestCancelled: return "xmark.circle"
        case .requestConfirmed: return "checkmark.circle"
        case .requestStillOn: return "hand.raised.fill"
        case .appOpened: return "iphone"
        }
    }
}
