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
    /// Enough settled rows for the aggregate to have a figure rather than "not enough yet".
    /// Party sizes and categories vary, because that is how the breakdowns get exercised.
    private(set) var outcomes: [PlanOutcome] = MockPlanOutcomeRepository.samples

    static let samples: [PlanOutcome] = {
        let now = Date()
        func row(_ type: PlanOutcomeType, _ size: Int, _ category: RequestCategory, _ hoursAgo: Int) -> PlanOutcome {
            PlanOutcome(
                outcome: type,
                groupSize: size,
                category: category,
                hadProposedTime: true,
                hoursBeforePlan: type == .cancelledLate ? 2 : nil,
                at: now.addingTimeInterval(TimeInterval(-3600 * hoursAgo))
            )
        }
        return [
            row(.agreed, 2, .relationship, 200), row(.agreed, 3, .friends, 190),
            row(.attended, 2, .relationship, 180), row(.attended, 2, .relationship, 170),
            row(.attended, 3, .friends, 160), row(.attended, 4, .friends, 150),
            row(.attended, 2, .dating, 140), row(.attended, 3, .friends, 130),
            // Ten settled rows, not nine: below ten the summary reports "not enough yet",
            // which is correct behaviour and useless as a fixture for the figure itself.
            row(.attended, 2, .chill, 125),
            row(.cancelledEarly, 2, .relationship, 120), row(.cancelledLate, 4, .friends, 110),
            row(.noShowed, 2, .daily, 100), row(.disputed, 3, .travel, 90)
        ]
    }()
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
