import Foundation
import Factory

@Observable
final class RequestService {
    private let repository: RequestRepository
    private let analytics = Container.shared.analyticsService()
    /// Separate from `analytics` on purpose: events are deleted after 90 days and with the
    /// account, which is right for usage data and fatal for a follow-through record. See
    /// `PlanOutcome`.
    private let planOutcomes = Container.shared.planOutcomeRepository()

    init(repository: RequestRepository) {
        self.repository = repository
    }

    func fetchRequests(for userID: String) async throws -> [Request] {
        try await repository.fetchRequests(for: userID)
    }

    func observeRequests(for userID: String) -> AsyncStream<[Request]> {
        repository.observeRequests(for: userID)
    }

    func createRequest(_ request: Request) async throws {
        try await repository.createRequest(request)
        await analytics.track(
            .requestCreated,
            userID: request.creatorID,
            requestID: request.id,
            metadata: ["category": request.category.rawValue]
        )
    }

    /// `proposedTime` is passed explicitly rather than read off `request`, which is a copy the
    /// caller loaded earlier. Inferring it would mean every response rewrote the time to whatever
    /// this client last saw — quietly undoing someone else's counter-offer.
    func respond(
        to request: Request,
        with response: ResponseType,
        text: String? = nil,
        proposedTime: Date? = nil,
        by userID: String
    ) async throws -> Request {
        // A fast local check. The authoritative one runs inside the transaction, against the
        // server's state rather than this copy.
        guard request.canRespond(as: userID) else {
            throw RequestError.notAllowedToRespond
        }

        let message = NegotiationMessage(
            senderID: userID,
            responseType: response,
            text: text
        )
        // Appended inside a transaction rather than written from this copy: in a group several
        // people can owe an answer at once, and anyone may comment at any time, so two writes
        // overlapping is ordinary. Writing the whole chain from a local copy loses one of them.
        // The permission check still runs — inside `addResponse`, against the server's state.
        let updated = try await repository.appendMessage(
            message,
            to: request.id,
            proposedTime: proposedTime
        )
        await analytics.trackResponse(response, to: request, by: userID)

        // The denominator. Recorded on the transition into `.accepted`, not on every response to
        // an already-accepted plan — a group plan stays open to further acceptances, so testing
        // the new status alone would count one night several times.
        if updated.status == .accepted, request.status != .accepted {
            await planOutcomes.record(.from(updated, outcome: .agreed))
        }
        return updated
    }

    /// Records whether an accepted plan actually happened.
    ///
    /// The only write permitted on a settled request, and the signal every reliability idea is
    /// computed from — until this existed, an accepted request simply stopped changing and
    /// `RequestStatus.completed` was a state nothing ever assigned.
    ///
    /// Writes only this user's own answer, mirroring `isConfirmingAttendance()` in
    /// firestore.rules. The status advances to `.completed` only when *everyone* has said it
    /// happened: one person cannot record the other as absent, and a disagreement stays
    /// unresolved rather than being decided in someone's favour.
    func confirmAttendance(
        of request: Request,
        outcome: ConfirmationOutcome,
        by userID: String
    ) async throws -> Request {
        guard request.needsConfirmation(from: userID) else {
            throw RequestError.notAllowedToConfirm
        }

        var updated = request
        updated.confirmations[userID] = outcome
        if updated.isConfirmedComplete {
            updated.status = .completed
        }
        // Nothing to write for the stake: its settlement is derived from these very
        // confirmations, so it resolves the moment the second answer lands.
        updated.updatedAt = Date()

        try await repository.updateRequest(updated)
        await analytics.track(
            .requestConfirmed,
            userID: userID,
            requestID: request.id,
            metadata: ["outcome": outcome.rawValue]
        )

        // Only the answer that completes the set settles the plan. Recording per answer would
        // count a two-person plan twice, and a three-person plan three times.
        if updated.everyoneHasAnswered {
            let settled: PlanOutcomeType = if updated.isConfirmedComplete {
                .attended
            } else if updated.isDisputed {
                .disputed
            } else {
                .noShowed
            }
            await planOutcomes.record(.from(updated, outcome: settled))
        }
        return updated
    }

    /// Makes one plan joinable by someone outside your groups.
    ///
    /// "Schedule a date with someone" — they get this plan, not your life. Deliberately not
    /// discovery: nothing is browsable, and the only way in is a code you hand over. The code
    /// goes on the request first so `isJoiningPlan` can check it without the joiner writing it.
    @discardableResult
    func createPlanInvite(for request: Request, by userID: String) async throws -> Request {
        guard request.creatorID == userID, request.isOpen else {
            throw RequestError.notAllowedToInvite
        }
        if let existing = request.planInviteCode, !existing.isEmpty { return request }

        let code = Relationship.generateInviteCode()
        var updated = request
        updated.planInviteCode = code
        // Room for exactly one more person. A one-off invite that admits everyone it is
        // forwarded to is not one-off, and the code travels by its nature — it is meant to be
        // sent to someone.
        updated.planInviteSeats = request.allParticipantIDs.count + 1
        updated.updatedAt = Date()
        try await repository.updateRequest(updated)
        try await repository.publishPlanInvite(code: code, requestID: request.id, ownerID: userID)
        return updated
    }

    /// Withdraws a plan invite, so every copy of the code stops working.
    ///
    /// Clearing the code is the revocation: `isJoiningPlan` requires a non-empty one.
    @discardableResult
    func revokePlanInvite(for request: Request, by userID: String) async throws -> Request {
        guard request.creatorID == userID else { throw RequestError.notAllowedToInvite }
        var updated = request
        updated.planInviteCode = nil
        updated.planInviteSeats = nil
        updated.updatedAt = Date()
        try await repository.updateRequest(updated)
        return updated
    }

    /// Redeems a plan-invite code, joining that one plan.
    ///
    /// Works entirely from the invite document, exactly like joining a group: the request is
    /// unreadable until this write lands, so there is nothing to check against beforehand.
    func joinPlan(inviteCode code: String, userID: String) async throws {
        let normalized = Relationship.normalizeInviteCode(code)
        guard let requestID = try await repository.planInvite(forCode: normalized) else {
            throw RequestError.inviteNotFound
        }
        try await repository.addParticipant(userID, to: requestID)
        await analytics.track(.inviteRedeemed, userID: userID, requestID: requestID)
    }

    /// Puts points on the plan happening. The other person must agree before it is live.
    func proposeStake(
        on request: Request,
        points: Int,
        by userID: String
    ) async throws -> Request {
        guard request.isOpen, request.isParticipant(userID), request.stake == nil else {
            throw RequestError.notAllowedToStake
        }
        var updated = request
        updated.stake = Stake(proposedBy: userID, points: points)
        updated.updatedAt = Date()
        try await repository.updateRequest(updated)
        return updated
    }

    /// Accepts the other person's proposed stake. Only they can — you cannot agree with yourself.
    func acceptStake(on request: Request, by userID: String) async throws -> Request {
        guard request.isOpen,
              let stake = request.stake,
              stake.canAccept(userID) else {
            throw RequestError.notAllowedToStake
        }
        var updated = request
        updated.stake?.acceptedBy = userID
        updated.updatedAt = Date()
        try await repository.updateRequest(updated)
        return updated
    }

    /// Withdraws a request, recording why.
    ///
    /// This used to delete the document. That erased the fact a plan had ever been made, so
    /// "cancelled three times in a row" could never mean anything — you cannot build a
    /// reliability signal on records that vanish when they become inconvenient. The request now
    /// moves to `.cancelled` and keeps its history; the other person still sees that it existed
    /// and why it was called off, which is the point of telling them at all.
    @discardableResult
    func cancel(
        _ request: Request,
        reason: CancellationReason?,
        by userID: String
    ) async throws -> Request {
        guard request.canCancel(as: userID) else {
            throw RequestError.notAllowedToCancel
        }
        var updated = request
        updated.status = .cancelled
        updated.cancellationReason = reason
        updated.updatedAt = Date()

        try await repository.updateRequest(updated)
        await analytics.track(
            .requestCancelled,
            userID: userID,
            requestID: request.id,
            metadata: reason.map { ["reason": $0.rawValue] } ?? [:]
        )
        // Early and late are separate outcomes, not one cancellation with a flag: the whole
        // argument about follow-through is that calling off a week ahead and calling off an hour
        // ahead are different acts.
        await planOutcomes.record(
            .from(updated, outcome: request.isCancellingLate() ? .cancelledLate : .cancelledEarly)
        )
        return updated
    }
}
