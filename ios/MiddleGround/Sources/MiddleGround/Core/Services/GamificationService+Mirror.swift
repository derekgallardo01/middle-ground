import Foundation

/// Pulling progress back from the server onto a device that has none.
///
/// Split out from `GamificationService` for the 500-line limit, and it is the right seam: this is
/// the only part of the service that reads from the mirror rather than writing to it, and the
/// only part that has to distinguish "the server holds nothing" from "the server could not be
/// reached". Everything else treats the mirror as a write-behind cache it never has to trust.
extension GamificationService {

    /// Restores progress from the server when the device has none — the case that used to lose
    /// a user's entire history on reinstall or device change.
    ///
    /// Restores the stats *and* the history: XP, level, streak and growth score, plus the
    /// achievements earned and the activity feed. Stats alone left a new device showing the
    /// numbers with nothing behind them — a level with no badges and no record of how it was
    /// reached.
    ///
    /// Callers invoke this on every load, so the attempt is recorded per user. Without that,
    /// a user who genuinely has no progress anywhere never populates the local store and would
    /// re-read the mirror on every single load — but only an attempt that *settled the question*
    /// counts.
    ///
    /// The marker used to be set before the read, so a restore that failed because the
    /// device was offline was never retried: come back online and the tab still showed Level 1 and
    /// 0 XP until the app was relaunched. A failure now leaves the marker off, and the returned
    /// `.unavailable` tells the caller not to present the defaults as facts.
    @discardableResult
    func restoreFromMirrorIfNeeded(for userID: String) async -> MirrorRestore {
        guard !restoreAttempted.contains(userID) else { return .notNeeded }
        guard let mirror, store.data(forKey: statsKey(for: userID)) == nil else {
            restoreAttempted.insert(userID)
            return .notNeeded
        }

        // Both of these read the *same* document, `gamification/{userID}`, and awaiting them in
        // sequence paid for that round trip twice — on the one screen whose whole job is to be
        // there when you open the tab.
        async let remoteStats = Self.attempt { try await mirror.stats(for: userID) }
        async let remoteHistory = Self.attempt { try await mirror.history(for: userID) }
        let (statsResult, historyResult) = await (remoteStats, remoteHistory)

        guard case .success(let stats) = statsResult else {
            // Not marked attempted: the next pull-to-refresh gets another go.
            MGLog.storage.info("Progress could not be restored from the mirror; will retry.")
            return .unavailable
        }
        restoreAttempted.insert(userID)

        if let stats, let data = try? JSONEncoder().encode(stats) {
            store.set(data, forKey: statsKey(for: userID))
        } else if stats == nil {
            // Reached the server and it holds nothing. A new account, and zeroes are the truth.
            return .nothingStored
        }

        // Written directly rather than through `save(achievements:)`, which would mirror
        // straight back to the server the values just read from it.
        guard case .success(let history) = historyResult, let history else { return .restored }
        if !history.achievements.isEmpty,
           let data = try? JSONEncoder().encode(history.achievements) {
            store.set(data, forKey: achievementsKey(for: userID))
        }
        if !history.activities.isEmpty,
           let data = try? JSONEncoder().encode(history.activities) {
            store.set(data, forKey: activitiesKey(for: userID))
        }
        return .restored
    }

    /// `Result(catching:)` has no async form, and the difference between "the server said nothing"
    /// and "the server was not reachable" is exactly what the caller needs — so `try?`, which
    /// flattens both into nil, is the one thing that cannot be used here.
    private static func attempt<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }
}
