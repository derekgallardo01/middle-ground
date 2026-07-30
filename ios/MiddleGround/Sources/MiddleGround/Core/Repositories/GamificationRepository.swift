import Foundation

/// Server-side mirror of a user's progress.
///
/// Progress previously lived only in `UserDefaults`, which meant two things: it vanished when
/// someone changed device, and none of it was measurable. Mirroring it fixes both — the local
/// store stays the fast path, this is the durable copy.
protocol GamificationRepository: Sendable {
    func stats(for userID: String) async throws -> GamificationStats?
    func save(_ stats: GamificationStats, for userID: String) async
    /// Admin read; denied to everyone else by `firestore.rules`.
    func allStats(limit: Int) async throws -> [String: GamificationStats]
}

actor MockGamificationRepository: GamificationRepository {
    private var storage: [String: GamificationStats] = [:]

    func stats(for userID: String) async throws -> GamificationStats? {
        storage[userID]
    }

    func save(_ stats: GamificationStats, for userID: String) async {
        storage[userID] = stats
    }

    func allStats(limit: Int) async throws -> [String: GamificationStats] {
        storage
    }
}
