import Foundation

/// Conversation about one plan.
///
/// A subcollection for the reasons set out on `PlanMessage`: the request document cannot carry
/// conversation without rewriting itself on every message, and the security rules cannot read a
/// subcollection, so decisions have to stay on the document while talk moves off it.
///
/// `observe` rather than `fetch` for the live view. A plan being arranged is exactly when people
/// are looking at it together, and polling a conversation is how you get a chat that feels a
/// second behind.
protocol PlanMessageRepository: Sendable {
    /// Newest `limit` messages, oldest-first once returned. Bounded because a long-running plan
    /// should not pay for its whole history every time the screen opens.
    func messages(forRequest requestID: String, limit: Int) async throws -> [PlanMessage]

    func observeMessages(forRequest requestID: String, limit: Int) -> AsyncStream<[PlanMessage]>

    /// Independent documents, so two people sending at once cannot overwrite each other —
    /// the failure the negotiation chain needed a transaction to avoid.
    func send(_ message: PlanMessage, forRequest requestID: String) async throws

    /// Removing your own. Editing is deliberately absent: a transcript people arrange an evening
    /// around should not silently change under them.
    func delete(messageID: String, forRequest requestID: String) async throws
}

extension PlanMessageRepository {
    static var defaultLimit: Int { 100 }
}

// MARK: - Mock

actor MockPlanMessageRepository: PlanMessageRepository {
    private var storage: [String: [PlanMessage]] = [:]
    private var continuations: [String: [UUID: AsyncStream<[PlanMessage]>.Continuation]] = [:]

    init(seed: [String: [PlanMessage]] = [:]) {
        storage = seed
    }

    func messages(forRequest requestID: String, limit: Int) async throws -> [PlanMessage] {
        Array((storage[requestID] ?? []).sorted { $0.at < $1.at }.suffix(limit))
    }

    nonisolated func observeMessages(
        forRequest requestID: String,
        limit: Int
    ) -> AsyncStream<[PlanMessage]> {
        AsyncStream { continuation in
            let token = UUID()
            Task {
                await self.register(continuation, token: token, for: requestID)
            }
            continuation.onTermination = { _ in
                Task { await self.stopObserving(requestID: requestID, token: token) }
            }
        }
    }

    private func register(
        _ continuation: AsyncStream<[PlanMessage]>.Continuation,
        token: UUID,
        for requestID: String
    ) {
        continuations[requestID, default: [:]][token] = continuation
        continuation.yield((storage[requestID] ?? []).sorted { $0.at < $1.at })
    }

    private func stopObserving(requestID: String, token: UUID) {
        continuations[requestID]?[token] = nil
    }

    func send(_ message: PlanMessage, forRequest requestID: String) async throws {
        storage[requestID, default: []].append(message)
        broadcast(requestID)
    }

    func delete(messageID: String, forRequest requestID: String) async throws {
        storage[requestID]?.removeAll { $0.id == messageID }
        broadcast(requestID)
    }

    private func broadcast(_ requestID: String) {
        let sorted = (storage[requestID] ?? []).sorted { $0.at < $1.at }
        continuations[requestID]?.values.forEach { $0.yield(sorted) }
    }

    /// Test affordance.
    func count(forRequest requestID: String) -> Int { storage[requestID]?.count ?? 0 }
}
