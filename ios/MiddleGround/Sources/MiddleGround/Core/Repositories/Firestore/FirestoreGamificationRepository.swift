import FirebaseFirestore
import Foundation

actor FirestoreGamificationRepository: GamificationRepository {
    /// Computed, not stored: constructing this type must not require FirebaseApp.configure().
    private var db: Firestore { Firestore.firestore() }
    private static let collection = "gamification"

    func stats(for userID: String) async throws -> GamificationStats? {
        let document = try await db.collection(Self.collection).document(userID).getDocument()
        guard document.exists else { return nil }
        return try? document.data(as: GamificationStatsDTO.self).toModel()
    }

    func save(_ stats: GamificationStats, for userID: String) async {
        // Best-effort: the local store is authoritative for the session, so a failed mirror
        // must not break the reward the user just earned.
        do {
            try db.collection(Self.collection)
                .document(userID)
                .setData(from: GamificationStatsDTO(from: stats), merge: true)
        } catch {
            MGLog.storage.error("Progress mirror failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func history(for userID: String) async throws -> MirroredHistory? {
        let document = try await db.collection(Self.collection).document(userID).getDocument()
        guard document.exists else { return nil }
        return try? document.data(as: MirroredHistoryDTO.self).toModel()
    }

    /// Writes into the same document as the stats, which is safe because every write here
    /// merges: the two paths touch disjoint fields and neither clobbers the other.
    func save(_ history: MirroredHistory, for userID: String) async {
        do {
            try db.collection(Self.collection)
                .document(userID)
                .setData(from: MirroredHistoryDTO(from: history), merge: true)
        } catch {
            MGLog.storage.error("History mirror failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func allStats(limit: Int) async throws -> [String: GamificationStats] {
        let snapshot = try await db.collection(Self.collection).limit(to: limit).getDocuments()
        var result: [String: GamificationStats] = [:]
        for document in snapshot.documents {
            if let stats = try? document.data(as: GamificationStatsDTO.self).toModel() {
                result[document.documentID] = stats
            }
        }
        return result
    }
}

private struct GamificationStatsDTO: Codable {
    var streakDays: Int
    var relationshipXP: Int
    var level: Int
    var growthScore: Int
    var nextLevelXP: Int
    var acceptedCount: Int
    var negotiatedCount: Int
    var weekendAcceptedCount: Int
    var lastResponseDate: Timestamp?
    /// Optional so mirrors written before per-category progression still decode.
    var categoryXP: [String: Int]?

    init(from stats: GamificationStats) {
        self.streakDays = stats.streakDays
        self.relationshipXP = stats.relationshipXP
        self.level = stats.level
        self.growthScore = stats.growthScore
        self.nextLevelXP = stats.nextLevelXP
        self.acceptedCount = stats.acceptedCount
        self.negotiatedCount = stats.negotiatedCount
        self.weekendAcceptedCount = stats.weekendAcceptedCount
        self.lastResponseDate = stats.lastResponseDate.map { Timestamp(date: $0) }
        self.categoryXP = stats.categoryXP
    }

    func toModel() -> GamificationStats {
        GamificationStats(
            streakDays: streakDays,
            relationshipXP: relationshipXP,
            level: level,
            growthScore: growthScore,
            nextLevelXP: nextLevelXP,
            acceptedCount: acceptedCount,
            negotiatedCount: negotiatedCount,
            weekendAcceptedCount: weekendAcceptedCount,
            lastResponseDate: lastResponseDate?.dateValue(),
            // Mirrored, so per-category progression survives a reinstall along with the rest of
            // the stats. Achievements and the activity feed ride in the same document via
            // MirroredHistoryDTO.
            categoryXP: categoryXP ?? [:]
        )
    }
}

/// Achievements and the activity feed, stored alongside the stats in the same document.
///
/// Both fields are optional so a mirror written before history was carried still decodes — the
/// same tolerance every other stored type in this app needs, and for the same reason: a schema
/// addition must never make older data unreadable.
private struct MirroredHistoryDTO: Codable {
    var achievements: [Achievement]?
    var activities: [Activity]?

    init(from history: MirroredHistory) {
        self.achievements = history.achievements
        // Newest first, then capped: if the feed has to be truncated, the entries worth keeping
        // are the recent ones.
        self.activities = Array(
            history.activities
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(MirroredHistory.activityLimit)
        )
    }

    func toModel() -> MirroredHistory {
        MirroredHistory(achievements: achievements ?? [], activities: activities ?? [])
    }
}
