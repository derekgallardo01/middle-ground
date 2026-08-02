import Foundation

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
    case notAllowedToConfirm
    case notAllowedToStake
    case notAllowedToInvite
    case inviteNotFound

    var errorDescription: String? {
        switch self {
        case .notAllowedToRespond:
            return "Only the person this was sent to can respond."
        case .notAllowedToCancel:
            return "Only the person who sent this can cancel it."
        case .notAllowedToConfirm:
            return "This plan isn't ready to confirm yet."
        case .notAllowedToStake:
            return "You can't put points on this plan."
        case .notAllowedToInvite:
            return "Only the person who created this plan can invite someone to it."
        case .inviteNotFound:
            return "That invite code doesn't match a plan."
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
    /// Group names sit in pickers and single-line rows, so they are capped far shorter.
    static let groupName = 40
    /// A place name, not an address essay.
    static let location = 120

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
    /// What each participant said about whether the plan happened, keyed by user ID.
    var confirmations: [String: ConfirmationOutcome]
    /// Why this was called off, when it was.
    var cancellationReason: CancellationReason?
    /// Points both people have riding on this actually happening.
    var stake: Stake?
    /// Set when this plan can be joined by someone outside your groups.
    ///
    /// A single-plan invite: they get this one plan, not your life. Nothing about it is
    /// discoverable — `invites` denies `list`, so the code has to have been given to them,
    /// and the request is unreadable until they redeem it.
    var planInviteCode: String?
    /// How many people the plan code may admit in total, including everyone already here.
    ///
    /// A one-off invite has to be one-off, or a forwarded code is an open door. The creator
    /// records the ceiling when issuing it, and the rules refuse any join that would exceed it.
    var planInviteSeats: Int?
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
         confirmations: [String: ConfirmationOutcome] = [:],
         cancellationReason: CancellationReason? = nil,
         stake: Stake? = nil,
         planInviteCode: String? = nil,
         planInviteSeats: Int? = nil,
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
        self.confirmations = confirmations
        self.cancellationReason = cancellationReason
        self.stake = stake
        self.planInviteCode = planInviteCode
        self.planInviteSeats = planInviteSeats
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Tolerates requests stored before attendance was recorded.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        creatorID = try container.decode(String.self, forKey: .creatorID)
        recipientIDs = try container.decode([String].self, forKey: .recipientIDs)
        category = try container.decode(RequestCategory.self, forKey: .category)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        proposedTime = try container.decodeIfPresent(Date.self, forKey: .proposedTime)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        status = try container.decode(RequestStatus.self, forKey: .status)
        negotiationChain = try container.decodeIfPresent(
            [NegotiationMessage].self, forKey: .negotiationChain
        ) ?? []
        confirmations = try container.decodeIfPresent(
            [String: ConfirmationOutcome].self, forKey: .confirmations
        ) ?? [:]
        cancellationReason = try container.decodeIfPresent(
            CancellationReason.self, forKey: .cancellationReason
        )
        stake = try container.decodeIfPresent(Stake.self, forKey: .stake)
        planInviteCode = try container.decodeIfPresent(String.self, forKey: .planInviteCode)
        planInviteSeats = try container.decodeIfPresent(Int.self, forKey: .planInviteSeats)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
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
        case .accepted, .declined, .completed, .cancelled:
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
    /// Responses that change *what is being proposed*, as opposed to answering it.
    ///
    /// A counter, a negotiation or a reschedule puts a different plan on the table, so everyone
    /// else owes a fresh answer to it — including people who had already replied to the previous
    /// version. Accepting and declining answer the current proposal; saving does neither.
    private static let proposalTypes: Set<ResponseType> = [.counter, .negotiate, .reschedule]

    /// More than two people, so "the other person" is not a thing.
    var isGroupPlan: Bool { allParticipantIDs.count > 2 }

    /// Whether anyone can still answer.
    ///
    /// Not the same as `isOpen`, and the difference is the whole of group plans. With two people
    /// an acceptance decides it and there is nothing left to say. With three, one friend saying
    /// yes must not lock the others out of saying yes too — the plan is on, and the people who
    /// have not answered still owe one.
    var acceptsResponses: Bool {
        switch status {
        case .completed, .cancelled, .declined:
            return false
        case .accepted:
            return isGroupPlan
        case .pending, .negotiated, .rescheduled, .countered, .saved:
            return true
        }
    }

    var awaitingResponseFrom: [String] {
        guard acceptsResponses else { return [] }

        // Whoever put the current proposal on the table, and everything said since.
        //
        // "Everyone except the last sender" was right for two people and wrong for three: after
        // B answered a three-person plan, it handed the turn back to the creator — who had
        // proposed it and owed nothing — while C, who had not replied at all, was not counted as
        // owing anything either. The turn belongs to whoever has not yet answered *this* version
        // of the plan.
        let proposalIndex = negotiationChain.lastIndex { Self.proposalTypes.contains($0.responseType) }
        let proposer = proposalIndex.map { negotiationChain[$0].senderID } ?? creatorID
        let since = proposalIndex.map { $0 + 1 } ?? 0

        let answered = Set(
            negotiationChain[since...]
                .filter { $0.responseType != .save }
                .map(\.senderID)
        )

        return allParticipantIDs.filter { $0 != proposer && !answered.contains($0) }
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

    /// Only the creator may call a plan off, and only while there is still a plan to call off.
    ///
    /// This used to require `isOpen`, which excluded `accepted` — so a plan could be cancelled
    /// only *before* anyone agreed to it, and became uncancellable the moment someone said yes.
    /// That is exactly backwards. Abandoning a plan nobody has agreed to costs no one anything;
    /// the plan people have arranged their evening around is precisely the one that has to be
    /// callable off. It also left the reliability score measuring something unreachable: a late
    /// cancellation could only ever have been a plan nobody had accepted.
    ///
    /// Confirmations are the stopping point. Once anyone has answered whether it happened, the
    /// plan is a record rather than a plan, and cancelling it would erase attendance somebody
    /// already reported.
    func canCancel(as userID: String) -> Bool {
        guard isCreator(userID) else { return false }
        switch status {
        case .completed, .cancelled, .declined:
            return false
        case .accepted, .pending, .negotiated, .rescheduled, .countered, .saved:
            return confirmations.isEmpty
        }
    }

    /// Whether calling this off *right now* would count as last-minute.
    ///
    /// The prospective twin of `wasCancelledLate`, which answers the same question after the
    /// fact from `updatedAt`. Both use the same window, so what the app warns you about and what
    /// the score later records cannot disagree.
    func isCancellingLate(at now: Date = Date()) -> Bool {
        guard let time = proposedTime else { return false }
        return time.timeIntervalSince(now) < ReliabilityScore.lateCancellationWindow
    }

    var isPending: Bool {
        status == .pending
    }

    // MARK: - Did it happen?
    //
    // Attendance is the input every reliability idea depends on, and the app collected none of
    // it: an accepted request simply stopped changing. These mirror `isConfirmingAttendance()`
    // in firestore.rules — the client must not offer an answer the backend will refuse.

    /// Only a dated plan can be asked about: "split the grocery run" has no moment to confirm.
    var isAwaitingAttendance: Bool {
        guard status == .accepted, let time = proposedTime else { return false }
        return time < Date()
    }

    /// Whether this person still owes an answer about whether it happened.
    func needsConfirmation(from userID: String) -> Bool {
        isAwaitingAttendance && isParticipant(userID) && confirmations[userID] == nil
    }

    /// Answers so far, in participant order, ignoring anyone who has not replied.
    private var recordedOutcomes: [ConfirmationOutcome] {
        allParticipantIDs.compactMap { confirmations[$0] }
    }

    var everyoneHasAnswered: Bool {
        recordedOutcomes.count == allParticipantIDs.count
    }

    /// Both said it happened — the only route to `.completed`.
    var isConfirmedComplete: Bool {
        everyoneHasAnswered && recordedOutcomes.allSatisfy { $0 == .happened }
    }

    /// They disagree about whether it happened.
    ///
    /// Deliberately its own state rather than a tie broken in someone's favour. One person
    /// cannot record the other as absent, and a contested outcome is what an appeal would
    /// later argue over — so it scores nothing either way.
    var isDisputed: Bool {
        everyoneHasAnswered && Set(recordedOutcomes).count > 1
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
        status = resolvedStatus(after: message)
        updatedAt = Date()
    }

    /// What the request's status becomes once `message` is on the chain.
    ///
    /// For two people this is the plain mapping and always was. For a group it is not: mapping a
    /// single decline straight to `declined` would let one person call off an evening three others
    /// had agreed to, which is not a decline — it is a cancellation, and only the creator may do
    /// that. So in a group a decline means "not me", and the plan is only declined once there is
    /// nobody left who might still come.
    private func resolvedStatus(after message: NegotiationMessage) -> RequestStatus {
        let mapped = message.responseType.statusMapping
        guard isGroupPlan, message.responseType == .decline else { return mapped }
        if hasAcceptance { return .accepted }
        return awaitingResponseFrom.isEmpty ? .declined : .pending
    }

    /// Whether anyone has said yes to the plan as it currently stands.
    ///
    /// Scoped to the current proposal: an acceptance of a time that has since been countered is
    /// not an acceptance of the new one.
    var hasAcceptance: Bool {
        let proposalIndex = negotiationChain.lastIndex { Self.proposalTypes.contains($0.responseType) }
        let since = proposalIndex.map { $0 + 1 } ?? 0
        return negotiationChain[since...].contains { $0.responseType == .accept }
    }

    /// Who has said they are coming — the creator included, since proposing is committing.
    var attendeeIDs: [String] {
        let proposalIndex = negotiationChain.lastIndex { Self.proposalTypes.contains($0.responseType) }
        let proposer = proposalIndex.map { negotiationChain[$0].senderID } ?? creatorID
        let since = proposalIndex.map { $0 + 1 } ?? 0
        let accepted = negotiationChain[since...]
            .filter { $0.responseType == .accept }
            .map(\.senderID)
        return ([proposer] + accepted).reduce(into: [String]()) { result, id in
            if !result.contains(id) { result.append(id) }
        }
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
