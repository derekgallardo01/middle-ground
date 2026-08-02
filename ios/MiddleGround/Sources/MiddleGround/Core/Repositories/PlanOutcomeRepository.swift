import Foundation

/// Persistence for the follow-through record.
///
/// Write-only from the app's point of view: nothing in the product reads these back, because
/// everything a *user* sees about reliability is computed from their own requests by
/// `ReliabilityScore`. This exists to answer operator questions months later, when the requests
/// it would otherwise have been computed from no longer exist.
///
/// See `PlanOutcome` for why the rows carry no user or request identifier.
protocol PlanOutcomeRepository: Sendable {
    /// Records one settled plan. Never throws into a caller — like analytics, this must not be
    /// able to fail the user action that triggered it.
    func record(_ outcome: PlanOutcome) async

    /// Records that someone went looking for a table. Same contract: never throws.
    func recordBookingIntent(_ intent: BookingIntent) async

    // MARK: - Admin reads

    func recentOutcomes(limit: Int) async throws -> [PlanOutcome]
}

// MARK: - Mock

actor MockPlanOutcomeRepository: PlanOutcomeRepository {
    private(set) var outcomes: [PlanOutcome] = []
    private(set) var bookingIntents: [BookingIntent] = []

    func record(_ outcome: PlanOutcome) async {
        outcomes.append(outcome)
    }

    func recordBookingIntent(_ intent: BookingIntent) async {
        bookingIntents.append(intent)
    }

    func recentOutcomes(limit: Int) async throws -> [PlanOutcome] {
        Array(outcomes.sorted { $0.at > $1.at }.prefix(limit))
    }

    /// Test affordance: how many of one kind were written.
    func count(of type: PlanOutcomeType) -> Int {
        outcomes.filter { $0.outcome == type }.count
    }
}
