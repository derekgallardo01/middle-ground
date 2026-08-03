import Foundation

/// Who has seen a plan.
///
/// Write-on-visit rather than write-on-render: one document per person per plan, refreshed when
/// they open it and when a new message arrives while they are looking. A receipt per message
/// would be a write per line per reader, which is the cost that makes read receipts expensive and
/// the social weight that makes them unpleasant.
protocol PlanReadReceiptRepository: Sendable {
    func observeReceipts(
        forRequest requestID: String,
        excluding userID: String
    ) -> AsyncStream<[PlanReadReceipt]>

    /// Records that this person has the plan open now. Failures are swallowed — a missing
    /// receipt is a cosmetic loss and must never interrupt reading.
    func markRead(userID: String, forRequest requestID: String) async
}

// MARK: - Mock

actor MockPlanReadReceiptRepository: PlanReadReceiptRepository {
    private var storage: [String: [String: PlanReadReceipt]] = [:]
    private var continuations: [String: [UUID: AsyncStream<[PlanReadReceipt]>.Continuation]] = [:]

    nonisolated func observeReceipts(
        forRequest requestID: String,
        excluding userID: String
    ) -> AsyncStream<[PlanReadReceipt]> {
        AsyncStream { continuation in
            let token = UUID()
            Task { await self.register(continuation, token: token, requestID: requestID, excluding: userID) }
            continuation.onTermination = { _ in
                Task { await self.unregister(token: token, requestID: requestID) }
            }
        }
    }

    private func register(
        _ continuation: AsyncStream<[PlanReadReceipt]>.Continuation,
        token: UUID,
        requestID: String,
        excluding userID: String
    ) {
        continuations[requestID, default: [:]][token] = continuation
        continuation.yield(current(requestID, excluding: userID))
    }

    private func unregister(token: UUID, requestID: String) {
        continuations[requestID]?[token] = nil
    }

    private func current(_ requestID: String, excluding userID: String) -> [PlanReadReceipt] {
        (storage[requestID] ?? [:]).values
            .filter { $0.userID != userID }
            .sorted { $0.readAt > $1.readAt }
    }

    func markRead(userID: String, forRequest requestID: String) async {
        storage[requestID, default: [:]][userID] = PlanReadReceipt(userID: userID, readAt: Date())
        let all = (storage[requestID] ?? [:]).values.sorted { $0.readAt > $1.readAt }
        continuations[requestID]?.values.forEach { $0.yield(all) }
    }

    /// Test affordance.
    func receiptCount(forRequest requestID: String) -> Int { storage[requestID]?.count ?? 0 }
}
