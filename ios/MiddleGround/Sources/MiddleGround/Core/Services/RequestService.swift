import Foundation
import Factory

@Observable
final class RequestService {
    private let repository: RequestRepository
    private let analytics = Container.shared.analyticsService()

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

    func respond(
        to request: Request,
        with response: ResponseType,
        text: String? = nil,
        by userID: String
    ) async throws -> Request {
        guard request.canRespond(as: userID) else {
            throw RequestError.notAllowedToRespond
        }

        var updated = request
        let message = NegotiationMessage(
            senderID: userID,
            responseType: response,
            text: text
        )
        try updated.addResponse(message)
        try await repository.updateRequest(updated)
        await analytics.trackResponse(response, to: request, by: userID)
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
        updated.updatedAt = Date()

        try await repository.updateRequest(updated)
        await analytics.track(
            .requestConfirmed,
            userID: userID,
            requestID: request.id,
            metadata: ["outcome": outcome.rawValue]
        )
        return updated
    }

    /// Withdraws a request. Only its creator may do this, and only while it is unanswered.
    func cancel(_ request: Request, by userID: String) async throws {
        guard request.canCancel(as: userID) else {
            throw RequestError.notAllowedToCancel
        }
        try await repository.deleteRequest(request)
        await analytics.track(.requestCancelled, userID: userID, requestID: request.id)
    }
}
