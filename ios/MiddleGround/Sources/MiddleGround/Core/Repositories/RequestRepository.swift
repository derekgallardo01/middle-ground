import Foundation

protocol RequestRepository: Sendable {
    func fetchRequests(for userID: String) async throws -> [Request]
    func createRequest(_ request: Request) async throws
    func updateRequest(_ request: Request) async throws
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
        .previewAwaitingMe, .previewNegotiating, .preview, .previewAccepted
    ]

    func fetchRequests(for userID: String) async throws -> [Request] {
        try await Task.sleep(nanoseconds: 300_000_000)
        return requests
    }

    func createRequest(_ request: Request) async throws {
        requests.insert(request, at: 0)
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
