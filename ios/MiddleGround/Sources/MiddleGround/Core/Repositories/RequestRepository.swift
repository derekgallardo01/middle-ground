import Foundation

protocol RequestRepository: Sendable {
    func fetchRequests(for userID: String) async throws -> [Request]
    func createRequest(_ request: Request) async throws
    func updateRequest(_ request: Request) async throws

    /// Appends one message atomically, and returns the request as it now stands.
    ///
    /// `updateRequest` writes the whole document from a copy the client read earlier, so two
    /// people answering at the same moment both append to *their* copy of the chain and the
    /// second write silently drops the first message. Turn-taking used to hide this — with two
    /// people only one could ever write — but a group plan can legitimately have several people
    /// owing an answer at once, and comments deliberately let anyone speak at any time. Both
    /// make the overlap ordinary rather than exotic.
    ///
    /// Doing the read inside a transaction also means the model validates the *server's* current
    /// state, not a snapshot from before someone else's write.
    func appendMessage(
        _ message: NegotiationMessage,
        to requestID: String,
        proposedTime: Date?
    ) async throws -> Request
    func deleteRequest(_ request: Request) async throws

    /// Publishes an invite that grants access to one plan.
    func publishPlanInvite(code: String, requestID: String, ownerID: String) async throws

    /// The request a plan-invite code points at, or nil if the code is unknown.
    func planInvite(forCode code: String) async throws -> String?

    /// Adds a participant, touching only the two membership arrays — `isJoiningPlan` in
    /// firestore.rules requires every other field to be byte-identical.
    func addParticipant(_ userID: String, to requestID: String) async throws
    func observeRequests(for userID: String) -> AsyncStream<[Request]>
}

actor MockRequestRepository: RequestRepository {
    // `previewAwaitingMe` is first on purpose: it is the only fixture the preview user can
    // actually respond to, so without it mock mode never renders the response row at all.
    private var requests: [Request] = [
        .previewAwaitingMe, .previewNegotiating, .previewHappeningNow, .previewStaked,
        .previewGroupPlan, .preview, .previewAccepted
    ]

    func fetchRequests(for userID: String) async throws -> [Request] {
        try await Task.sleep(nanoseconds: 300_000_000)
        return requests
    }

    func createRequest(_ request: Request) async throws {
        requests.insert(request, at: 0)
    }

    /// Serial by construction, being an actor — which is exactly the property the Firestore
    /// implementation has to buy with a transaction.
    func appendMessage(
        _ message: NegotiationMessage,
        to requestID: String,
        proposedTime: Date?
    ) async throws -> Request {
        guard let index = requests.firstIndex(where: { $0.id == requestID }) else {
            throw RequestError.notAllowedToRespond
        }
        var request = requests[index]
        if let proposedTime { request.proposedTime = proposedTime }
        try request.addResponse(message)
        requests[index] = request
        return request
    }

    func updateRequest(_ request: Request) async throws {
        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            requests[index] = request
        }
    }

    func deleteRequest(_ request: Request) async throws {
        requests.removeAll { $0.id == request.id }
    }

    private var planInvites: [String: String] = [:]

    func publishPlanInvite(code: String, requestID: String, ownerID: String) async throws {
        planInvites[code] = requestID
    }

    func planInvite(forCode code: String) async throws -> String? {
        planInvites[Relationship.normalizeInviteCode(code)]
    }

    func addParticipant(_ userID: String, to requestID: String) async throws {
        guard let index = requests.firstIndex(where: { $0.id == requestID }) else { return }
        requests[index].recipientIDs.append(userID)
    }

    nonisolated func observeRequests(for userID: String) -> AsyncStream<[Request]> {
        AsyncStream { continuation in
            Task {
                continuation.yield(await self.requests)
                continuation.finish()
            }
        }
    }
}
