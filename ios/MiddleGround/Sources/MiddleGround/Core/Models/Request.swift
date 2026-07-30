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

    var isPending: Bool {
        status == .pending
    }

    mutating func addResponse(_ message: NegotiationMessage) {
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
