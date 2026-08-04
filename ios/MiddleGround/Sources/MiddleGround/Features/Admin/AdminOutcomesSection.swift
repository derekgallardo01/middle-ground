import SwiftUI

/// What share of agreed plans actually happen.
///
/// Its own file for the same reason as the venues section: `AdminView` is at the file-length
/// limit, and this is a self-contained read.
///
/// Operator-only, and it has to be: `plan_outcomes` is readable by admins alone, and the rows
/// carry no user or request, so nothing here can be attributed to anybody. That is the point —
/// it is the number `docs/partnerships/opentable.md` offers a partner, not a number about a
/// person.
struct AdminOutcomesSection: View {
    let summary: OutcomeSummary
    let outcomes: [PlanOutcome]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headline

            if !outcomes.isEmpty {
                breakdown(
                    "By party size",
                    rows: OutcomeSummary.byPartySize(outcomes).map {
                        ($0.size == 2 ? "2 people" : "\($0.size) people", $0.summary)
                    }
                )
                breakdown(
                    "By kind of plan",
                    rows: OutcomeSummary.byCategory(outcomes).map {
                        ($0.category.displayName, $0.summary)
                    }
                )
            }

            Text("""
            Collection began 2 August 2026. Nothing before that exists and it cannot be \
            reconstructed — worth saying out loud whenever this figure is quoted.
            """)
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm600)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Follow-through")
                .mgFont(.h3)

            if let percentage = summary.followThroughPercentage {
                Text("\(percentage)%")
                    .mgFont(.h1)
                    .monospacedDigit()
                Text("of settled plans happened, across \(summary.settled) plans.")
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)

                if let late = summary.lateCancellationPercentage {
                    Text("\(late)% were called off at short notice — the number a restaurant minds.")
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.warm600)
                }
            } else {
                Text("Not enough settled plans yet — \(summary.untilMeaningful) to go.")
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)
            }

            counts
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mgSurfaceCard()
    }

    private var counts: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Agreed", summary.agreed)
            row("Happened", summary.attended)
            row("Called off early", summary.cancelledEarly)
            row("Called off late", summary.cancelledLate)
            row("Nobody turned up", summary.noShowed)
            row("Disputed", summary.disputed)
        }
        .padding(.top, 4)
    }

    private func breakdown(_ title: String, rows: [(String, OutcomeSummary)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .mgFont(.h3)
            ForEach(rows, id: \.0) { label, summary in
                HStack {
                    Text(label)
                        .mgFont(.bodySmall)
                    Spacer()
                    Text(summary.followThroughPercentage.map { "\($0)%" } ?? "—")
                        .mgFont(.bodySmall)
                        .monospacedDigit()
                        .foregroundStyle(MGColors.warm600)
                    Text("(\(summary.settled))")
                        .mgFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(MGColors.warm400)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mgSurfaceCard()
    }

    private func row(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)
            Spacer()
            Text("\(value)")
                .mgFont(.bodySmall)
                .monospacedDigit()
        }
    }
}
