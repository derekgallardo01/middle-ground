import Foundation

/// Who in a group has said they are not free, and when.
///
/// Scoped to a group, because that is the only membership the security rules can prove by reading
/// a single document. See `SharedAvailability`.
protocol AvailabilityRepository: Sendable {
    /// Everyone's blocked time in one group, the reader included.
    func availability(forGroup groupID: String) async throws -> [SharedAvailability]

    func observeAvailability(forGroup groupID: String) -> AsyncStream<[SharedAvailability]>

    /// Writes your own, to one group. Called once per group you are sharing with.
    func save(_ availability: SharedAvailability, forGroup groupID: String) async throws
}

// MARK: - Mock

actor MockAvailabilityRepository: AvailabilityRepository {
    private var storage: [String: [String: SharedAvailability]]
    private var continuations: [String: [UUID: AsyncStream<[SharedAvailability]>.Continuation]] = [:]

    /// Sam is away for a couple of days, so the calendar has something to show in mock mode.
    init(seed: [String: [String: SharedAvailability]] = MockAvailabilityRepository.samples) {
        storage = seed
    }

    static let samples: [String: [String: SharedAvailability]] = {
        let calendar = Calendar.current
        let inTwoDays = calendar.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        let inThreeDays = calendar.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return [
            "rel_1": [
                "user_2": SharedAvailability(
                    userID: "user_2",
                    blocks: [
                        .wholeDay(inTwoDays),
                        .wholeDay(inThreeDays)
                    ]
                )
            ]
        ]
    }()

    func availability(forGroup groupID: String) async throws -> [SharedAvailability] {
        Array((storage[groupID] ?? [:]).values).sorted { $0.userID < $1.userID }
    }

    nonisolated func observeAvailability(forGroup groupID: String) -> AsyncStream<[SharedAvailability]> {
        AsyncStream { continuation in
            let token = UUID()
            Task { await self.register(continuation, token: token, groupID: groupID) }
            continuation.onTermination = { _ in
                Task { await self.unregister(token: token, groupID: groupID) }
            }
        }
    }

    private func register(
        _ continuation: AsyncStream<[SharedAvailability]>.Continuation,
        token: UUID,
        groupID: String
    ) {
        continuations[groupID, default: [:]][token] = continuation
        continuation.yield(Array((storage[groupID] ?? [:]).values).sorted { $0.userID < $1.userID })
    }

    private func unregister(token: UUID, groupID: String) {
        continuations[groupID]?[token] = nil
    }

    func save(_ availability: SharedAvailability, forGroup groupID: String) async throws {
        storage[groupID, default: [:]][availability.userID] = availability
        let all = Array((storage[groupID] ?? [:]).values).sorted { $0.userID < $1.userID }
        continuations[groupID]?.values.forEach { $0.yield(all) }
    }

    /// Test affordance.
    func blockCount(forGroup groupID: String, userID: String) -> Int {
        storage[groupID]?[userID]?.blocks.count ?? 0
    }
}
