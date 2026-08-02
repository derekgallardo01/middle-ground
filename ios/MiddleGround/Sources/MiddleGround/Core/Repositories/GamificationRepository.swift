import Foundation

/// Server-side mirror of a user's progress.
///
/// Progress previously lived only in `UserDefaults`, which meant two things: it vanished when
/// someone changed device, and none of it was measurable. Mirroring it fixes both — the local
/// store stays the fast path, this is the durable copy.
/// What someone earned, as opposed to where they got to.
///
/// Only `GamificationStats` was ever mirrored, so a reinstall restored XP, level and streak but
/// started achievements and the entire activity history from empty — every badge lost, every
/// entry in the feed gone, with the numbers intact beside them. Carrying these too is what makes
/// "your progress survives a new phone" true rather than nearly true.
struct MirroredHistory: Codable, Sendable, Equatable {
    var achievements: [Achievement]
    var activities: [Activity]

    /// The feed is unbounded locally but shares a 1MB Firestore document with everything else,
    /// so only the most recent entries are carried. Losing the tail of an old feed on a device
    /// change is a far smaller loss than the mirror silently failing to write at all.
    static let activityLimit = 100
}

protocol GamificationRepository: Sendable {
    func stats(for userID: String) async throws -> GamificationStats?
    func save(_ stats: GamificationStats, for userID: String) async
    func history(for userID: String) async throws -> MirroredHistory?
    func save(_ history: MirroredHistory, for userID: String) async
    /// Admin read; denied to everyone else by `firestore.rules`.
    func allStats(limit: Int) async throws -> [String: GamificationStats]
}

actor MockGamificationRepository: GamificationRepository {
    private var storage: [String: GamificationStats] = [:]
    private var histories: [String: MirroredHistory] = [:]

    func stats(for userID: String) async throws -> GamificationStats? {
        storage[userID]
    }

    func save(_ stats: GamificationStats, for userID: String) async {
        storage[userID] = stats
    }

    func history(for userID: String) async throws -> MirroredHistory? {
        histories[userID]
    }

    func save(_ history: MirroredHistory, for userID: String) async {
        histories[userID] = history
    }

    func allStats(limit: Int) async throws -> [String: GamificationStats] {
        storage
    }
}
