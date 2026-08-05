import Foundation

/// Storage for requests to look again at a contested plan.
///
/// Write-mostly from the app's side: somebody raises one and never sees it again, because there
/// is nothing for them to do with it. Reading is an operator's job, the same shape as `reports`.
protocol DisputeRepository: Sendable {
    /// Raises a dispute. Throws, unlike analytics — somebody asking to be heard must be told if
    /// it failed rather than left believing it was filed.
    func raise(_ dispute: PlanDispute) async throws

    // MARK: - Admin reads

    func recentDisputes(limit: Int) async throws -> [PlanDispute]

    /// Records what was decided, and who decided it. Admin-only, enforced in the rules.
    func resolveDispute(id: String, as resolution: ReportResolution, by adminID: String) async throws
}

// MARK: - Mock

actor MockDisputeRepository: DisputeRepository {
    /// One waiting and one already decided, so both halves of the queue can be driven.
    private var disputes: [PlanDispute] = [
        PlanDispute(
            id: "dispute_open",
            raisedBy: User.preview2.id,
            requestID: "req_5",
            planTitle: "Coffee on Monday",
            note: "I was there and waited half an hour.",
            at: Date().addingTimeInterval(-7_200)
        ),
        PlanDispute(
            id: "dispute_done",
            raisedBy: User.preview.id,
            requestID: "req_4",
            planTitle: "Climbing on Saturday",
            note: nil,
            at: Date().addingTimeInterval(-172_800),
            resolution: .dismissed,
            resolvedBy: "root",
            resolvedAt: Date().addingTimeInterval(-160_000)
        )
    ]

    func raise(_ dispute: PlanDispute) async throws {
        disputes.append(dispute)
    }

    func recentDisputes(limit: Int) async throws -> [PlanDispute] {
        Array(disputes.sorted { $0.at > $1.at }.prefix(limit))
    }

    func resolveDispute(id: String, as resolution: ReportResolution, by adminID: String) async throws {
        guard let index = disputes.firstIndex(where: { $0.id == id }) else { return }
        let existing = disputes[index]
        disputes[index] = PlanDispute(
            id: existing.id,
            raisedBy: existing.raisedBy,
            requestID: existing.requestID,
            planTitle: existing.planTitle,
            note: existing.note,
            at: existing.at,
            resolution: resolution,
            resolvedBy: adminID,
            resolvedAt: Date()
        )
    }

    /// Test affordance.
    func count() -> Int { disputes.count }
}
