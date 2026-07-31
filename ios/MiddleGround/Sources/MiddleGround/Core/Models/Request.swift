import Foundation

enum RequestCategory: String, Codable, CaseIterable, Identifiable {
    case relationship
    case friends
    case family
    case daily
    case travel
    case spontaneous

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .relationship: return "Relationship"
        case .friends: return "Friends"
        case .family: return "Family"
        case .daily: return "Daily Life"
        case .travel: return "Travel"
        case .spontaneous: return "Spontaneous"
        }
    }

    var iconName: String {
        switch self {
        case .relationship: return "heart.fill"
        case .friends: return "person.2.fill"
        case .family: return "house.fill"
        case .daily: return "checklist"
        case .travel: return "airplane"
        case .spontaneous: return "bolt.fill"
        }
    }
}

enum ResponseType: String, Codable, CaseIterable, Identifiable {
    case accept
    case decline
    case negotiate
    case reschedule
    case counter
    case save

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accept: return "Accept"
        case .decline: return "Decline"
        case .negotiate: return "Negotiate"
        case .reschedule: return "Reschedule"
        case .counter: return "Counter"
        case .save: return "Save"
        }
    }

    var emoji: String {
        switch self {
        case .accept: return "✅"
        case .decline: return "❌"
        case .negotiate: return "🤝"
        case .reschedule: return "⏰"
        case .counter: return "📝"
        case .save: return "❤️"
        }
    }

    /// Past-tense phrasing for the activity feed.
    var activityDescription: String {
        switch self {
        case .accept: return "Accepted a request"
        case .decline: return "Declined a request"
        case .negotiate: return "Found a middle ground"
        case .reschedule: return "Rescheduled a plan"
        case .counter: return "Sent a counter-offer"
        case .save: return "Saved a request for later"
        }
    }
}

enum RequestStatus: String, Codable, Identifiable {
    case pending
    case accepted
    case declined
    case negotiated
    case rescheduled
    case countered
    case saved
    case completed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .negotiated: return "Negotiating"
        case .rescheduled: return "Rescheduled"
        case .countered: return "Countered"
        case .saved: return "Saved"
        case .completed: return "Completed"
        }
    }
}

struct NegotiationMessage: Identifiable, Hashable, Codable {
    let id: String
    let senderID: String
    let responseType: ResponseType
    let text: String?
    let timestamp: Date

    init(id: String = UUID().uuidString,
         senderID: String,
         responseType: ResponseType,
         text: String? = nil,
         timestamp: Date = Date()) {
        self.id = id
        self.senderID = senderID
        self.responseType = responseType
        self.text = text
        self.timestamp = timestamp
    }
}

enum RequestError: LocalizedError, Equatable {
    case notAllowedToRespond
    case notAllowedToCancel

    var errorDescription: String? {
        switch self {
        case .notAllowedToRespond:
            return "Only the person this was sent to can respond."
        case .notAllowedToCancel:
            return "Only the person who sent this can cancel it."
        }
    }
}

/// Caps on anything a user types.
///
/// Only "not empty" was ever checked, so a long paste sailed through to Firestore and failed
/// against the 1 MB document limit — surfacing as a generic "Failed to send" with the text
/// lost. The negotiation chain makes that worse: every message is appended to the *same*
/// document, so the ceiling is shared across the whole conversation.
enum RequestLimits {
    static let title = 120
    static let details = 1_000
    static let message = 1_000
    static let reportNote = 500

    /// Trims to `limit` without splitting a grapheme cluster (an emoji stays whole).
    static func clamp(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit))
    }
}

struct Request: Identifiable, Hashable, Codable {
    let id: String
    var creatorID: String
    var recipientIDs: [String]
    var category: RequestCategory
    var title: String
    var details: String?
    var proposedTime: Date?
    var location: String?
    var status: RequestStatus
    var negotiationChain: [NegotiationMessage]
    var savedForLater: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         creatorID: String,
         recipientIDs: [String],
         category: RequestCategory,
         title: String,
         details: String? = nil,
         proposedTime: Date? = nil,
         location: String? = nil,
         status: RequestStatus = .pending,
         negotiationChain: [NegotiationMessage] = [],
         savedForLater: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.creatorID = creatorID
        self.recipientIDs = recipientIDs
        self.category = category
        self.title = title
        self.details = details
        self.proposedTime = proposedTime
        self.location = location
        self.status = status
        self.negotiationChain = negotiationChain
        self.savedForLater = savedForLater
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var allParticipantIDs: [String] {
        Array(Set([creatorID] + recipientIDs))
    }

    // MARK: - Roles
    //
    // A shared decision only means something if the *other* person answers it. Without these
    // checks a creator could accept their own request, close the decision unilaterally, and
    // collect the XP — so the rule is enforced here, in the service, in the UI, and in
    // firestore.rules.

    /// True when `userID` was asked to respond to this request.
    func isRecipient(_ userID: String) -> Bool {
        recipientIDs.contains(userID)
    }

    func isCreator(_ userID: String) -> Bool {
        creatorID == userID
    }

    func isParticipant(_ userID: String) -> Bool {
        allParticipantIDs.contains(userID)
    }

    /// Whether the conversation is still going.
    ///
    /// Only accepting, declining or completing settles a decision. Countering, negotiating and
    /// rescheduling are *moves within* the conversation, not the end of it — treating them as
    /// terminal is what previously froze a request the moment anyone replied.
    var isOpen: Bool {
        switch status {
        case .accepted, .declined, .completed:
            return false
        case .pending, .negotiated, .rescheduled, .countered, .saved:
            return true
        }
    }

    /// Whose turn it is to answer.
    ///
    /// Before anyone has replied, the recipients owe the answer. After that the turn belongs to
    /// whoever did *not* send the last real message — which is what lets a counter come back to
    /// the creator so they can accept it.
    ///
    /// Saving is skipped deliberately: it is a bookmark ("not right now"), not an answer, so it
    /// must not hand the turn to the other person or demand anything of them.
    var awaitingResponseFrom: [String] {
        guard isOpen else { return [] }
        guard let lastAnswer = negotiationChain.last(where: { $0.responseType != .save }) else {
            return recipientIDs
        }
        return allParticipantIDs.filter { $0 != lastAnswer.senderID }
    }

    /// Whether `userID` may accept / decline / negotiate / counter / reschedule / save.
    ///
    /// The single gate for the UI, `RequestService` and `firestore.rules` alike.
    func canRespond(as userID: String) -> Bool {
        awaitingResponseFrom.contains(userID)
    }

    /// This user has replied and is waiting on the other person.
    func isAwaitingResponse(for userID: String) -> Bool {
        isOpen && isParticipant(userID) && !canRespond(as: userID)
    }

    /// Only the creator may withdraw a request, and only while it is unsettled.
    func canCancel(as userID: String) -> Bool {
        isOpen && isCreator(userID)
    }

    var isPending: Bool {
        status == .pending
    }

    /// Appends a response and advances the status.
    ///
    /// Throws rather than silently ignoring an invalid responder: a caller that gets this wrong
    /// has a bug, and swallowing it would let the UI show a state the backend rejects.
    mutating func addResponse(_ message: NegotiationMessage) throws {
        guard canRespond(as: message.senderID) else {
            throw RequestError.notAllowedToRespond
        }
        negotiationChain.append(message)
        status = message.responseType.statusMapping
        updatedAt = Date()
    }
}

extension ResponseType {
    var statusMapping: RequestStatus {
        switch self {
        case .accept: return .accepted
        case .decline: return .declined
        case .negotiate: return .negotiated
        case .reschedule: return .rescheduled
        case .counter: return .countered
        case .save: return .saved
        }
    }
}

extension Request {
    static let preview = Request(
        id: "req_1",
        creatorID: User.preview.id,
        recipientIDs: [User.preview2.id],
        category: .relationship,
        title: "Date night this Friday?",
        details: "Want to try that new Italian place?",
        proposedTime: Date().addingTimeInterval(86400 * 3),
        status: .pending
    )

    static let previewNegotiating = Request(
        id: "req_2",
        creatorID: User.preview.id,
        recipientIDs: [User.preview2.id],
        category: .friends,
        title: "Dinner Tonight?",
        details: "Pizza at 7?",
        status: .negotiated,
        negotiationChain: [
            NegotiationMessage(senderID: User.preview2.id, responseType: .counter, text: "Can we do 8 instead?"),
            NegotiationMessage(senderID: User.preview.id, responseType: .accept, text: "Works for me!")
        ]
    )

    static let previewAccepted = Request(
        id: "req_3",
        creatorID: User.preview.id,
        recipientIDs: [User.preview2.id],
        category: .travel,
        title: "Weekend Getaway",
        details: "Beach house May 24–26",
        status: .accepted
    )
}
