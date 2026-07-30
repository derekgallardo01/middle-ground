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
            lastResponseDate: lastResponseDate?.dateValue()
        )
    }
}
