import Foundation
import FirebaseFirestore

// MARK: - Request DTO

struct RequestDTO: Codable, Identifiable {
    @DocumentID var id: String?
    var creatorID: String
    var recipientIDs: [String]
    var category: String
    var title: String
    var details: String?
    var proposedTime: Timestamp?
    var location: String?
    var status: String
    var negotiationChain: [NegotiationMessageDTO]
    /// Optional so requests written before attendance was recorded still decode.
    var confirmations: [String: String]?
    /// Optional: only set when a plan was called off.
    var cancellationReason: String?
    /// Optional: only set once someone proposes points on the plan.
    var stake: Stake?
    var planInviteCode: String?
    var planInviteSeats: Int?
    var allParticipantIDs: [String]
    var createdAt: Timestamp
    var updatedAt: Timestamp

    init(from request: Request) {
        self.id = request.id
        self.creatorID = request.creatorID
        self.recipientIDs = request.recipientIDs
        self.category = request.category.rawValue
        self.title = request.title
        self.details = request.details
        self.proposedTime = request.proposedTime.map { Timestamp(date: $0) }
        self.location = request.location
        self.status = request.status.rawValue
        self.negotiationChain = request.negotiationChain.map { NegotiationMessageDTO(from: $0) }
        self.confirmations = request.confirmations.mapValues(\.rawValue)
        self.cancellationReason = request.cancellationReason?.rawValue
        self.stake = request.stake
        self.planInviteCode = request.planInviteCode
        self.planInviteSeats = request.planInviteSeats
        self.allParticipantIDs = request.allParticipantIDs
        self.createdAt = Timestamp(date: request.createdAt)
        self.updatedAt = Timestamp(date: request.updatedAt)
    }

    func toModel() -> Request? {
        // An unrecognised category no longer discards the request.
        //
        // This guard used to include `RequestCategory(rawValue:)`, so a category added in a later
        // release made every request using it silently vanish for anyone on an older build — the
        // repository `compactMap`s, so there was no error to notice. Status still fails closed:
        // a request whose state cannot be read cannot be safely acted on, whereas one whose
        // category cannot be read is merely unlabelled.
        guard let id, let statusEnum = RequestStatus(rawValue: status) else {
            return nil
        }

        return Request(
            id: id,
            creatorID: creatorID,
            recipientIDs: recipientIDs,
            category: RequestCategory(storedValue: category),
            title: title,
            details: details,
            proposedTime: proposedTime?.dateValue(),
            location: location,
            status: statusEnum,
            negotiationChain: negotiationChain.compactMap { $0.toModel() },
            // An unrecognised outcome is dropped rather than failing the whole request, for the
            // same reason an unknown category no longer does.
            confirmations: (confirmations ?? [:]).compactMapValues(ConfirmationOutcome.init(rawValue:)),
            cancellationReason: cancellationReason.flatMap(CancellationReason.init(rawValue:)),
            stake: stake,
            planInviteCode: planInviteCode,
            planInviteSeats: planInviteSeats,
            createdAt: createdAt.dateValue(),
            updatedAt: updatedAt.dateValue()
        )
    }
}

struct NegotiationMessageDTO: Codable, Identifiable {
    var id: String
    var senderID: String
    var responseType: String
    var text: String?
    var timestamp: Timestamp

    init(from message: NegotiationMessage) {
        self.id = message.id
        self.senderID = message.senderID
        self.responseType = message.responseType.rawValue
        self.text = message.text
        self.timestamp = Timestamp(date: message.timestamp)
    }

    func toModel() -> NegotiationMessage? {
        guard let responseEnum = ResponseType(rawValue: responseType) else { return nil }
        return NegotiationMessage(
            id: id,
            senderID: senderID,
            responseType: responseEnum,
            text: text,
            timestamp: timestamp.dateValue()
        )
    }
}

// MARK: - User DTO

struct UserDTO: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var avatarURL: String?
    var createdAt: Timestamp

    init(from user: User) {
        self.id = user.id
        self.name = user.name
        self.avatarURL = user.avatarURL?.absoluteString
        self.createdAt = Timestamp(date: user.createdAt)
    }

    func toModel() -> User? {
        guard let id else { return nil }
        return User(
            id: id,
            name: name,
            avatarURL: avatarURL.flatMap { URL(string: $0) },
            createdAt: createdAt.dateValue()
        )
    }
}

// MARK: - Relationship DTO

struct RelationshipDTO: Codable, Identifiable {
    @DocumentID var id: String?
    var participantIDs: [String]
    var type: String
    var createdAt: Timestamp
    var growthScore: Int
    /// Optional so documents written before groups could be named still decode.
    var name: String?
    var inviteCode: String
    /// How many people this group may hold.
    ///
    /// Optional for the same reason, and it carries more weight than `name` does: absence means
    /// two, matching what every group written before this field could actually hold. Decoding it
    /// as unlimited would silently widen every existing couple.
    var seats: Int?

    init(from relationship: Relationship) {
        self.id = relationship.id
        self.participantIDs = relationship.participantIDs
        self.type = relationship.type.rawValue
        self.createdAt = Timestamp(date: relationship.createdAt)
        self.growthScore = relationship.growthScore
        self.name = relationship.name
        self.inviteCode = relationship.inviteCode
        self.seats = relationship.seatCount
    }

    func toModel() -> Relationship? {
        guard let id,
              let typeEnum = RelationshipType(rawValue: type) else {
            return nil
        }
        return Relationship(
            id: id,
            participantIDs: participantIDs,
            type: typeEnum,
            createdAt: createdAt.dateValue(),
            growthScore: growthScore,
            name: name,
            inviteCode: inviteCode,
            seats: seats ?? 2
        )
    }
}
