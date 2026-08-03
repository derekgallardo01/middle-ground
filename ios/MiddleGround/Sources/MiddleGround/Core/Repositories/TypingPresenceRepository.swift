import Foundation

/// Who is typing on a plan.
///
/// Write-mostly and disposable. Nothing here is worth a retry, an error message, or a moment of
/// the user's attention — a missed heartbeat means an indicator flickers, which is the correct
/// severity for this feature.
protocol TypingPresenceRepository: Sendable {
    /// Everyone currently typing except `excluding`. Expired entries are filtered here as well as
    /// deleted by TTL, because TTL is eventual and a stale "typing…" is the whole failure mode.
    func observeTyping(
        forRequest requestID: String,
        excluding userID: String
    ) -> AsyncStream<[TypingPresence]>

    /// Refreshes this user's flag. Called on a heartbeat while someone keeps typing.
    func startTyping(userID: String, forRequest requestID: String) async

    /// Clears it immediately, for the ordinary cases — sending, or closing the screen.
    func stopTyping(userID: String, forRequest requestID: String) async
}

// MARK: - Mock

actor MockTypingPresenceRepository: TypingPresenceRepository {
    /// Opt-in, unlike the message and receipt seeds.
    ///
    /// Typing is a momentary state, and seeding it by default would put a permanent
    /// "Sam is typing" into every screenshot and demo — saying something that is not true of a
    /// still image. `-MGSeedTyping` turns it on for the tests that need to see the indicator.
    private var storage: [String: [String: TypingPresence]] = {
        guard AppConfiguration.seedsTypingIndicator else { return [:] }
        return [
            "req_6": [
                "user_2": TypingPresence(
                    userID: "user_2",
                    startedAt: Date(),
                    // Far enough out that it survives the run rather than expiring mid-test.
                    expiresAt: Date().addingTimeInterval(3600)
                )
            ]
        ]
    }()
    private var continuations: [String: [UUID: AsyncStream<[TypingPresence]>.Continuation]] = [:]

    nonisolated func observeTyping(
        forRequest requestID: String,
        excluding userID: String
    ) -> AsyncStream<[TypingPresence]> {
        AsyncStream { continuation in
            let token = UUID()
            Task { await self.register(continuation, token: token, requestID: requestID, excluding: userID) }
            continuation.onTermination = { _ in
                Task { await self.unregister(token: token, requestID: requestID) }
            }
        }
    }

    private func register(
        _ continuation: AsyncStream<[TypingPresence]>.Continuation,
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

    private func current(_ requestID: String, excluding userID: String) -> [TypingPresence] {
        (storage[requestID] ?? [:]).values
            .filter { $0.userID != userID && !$0.hasExpired() }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func startTyping(userID: String, forRequest requestID: String) async {
        storage[requestID, default: [:]][userID] = TypingPresence(userID: userID)
        broadcast(requestID)
    }

    func stopTyping(userID: String, forRequest requestID: String) async {
        storage[requestID]?[userID] = nil
        broadcast(requestID)
    }

    private func broadcast(_ requestID: String) {
        let all = (storage[requestID] ?? [:]).values.filter { !$0.hasExpired() }
        for continuation in continuations[requestID]?.values ?? [:].values {
            continuation.yield(all.sorted { $0.startedAt < $1.startedAt })
        }
    }

    /// Test affordance.
    func typingCount(forRequest requestID: String) -> Int {
        (storage[requestID] ?? [:]).values.filter { !$0.hasExpired() }.count
    }
}
