import SwiftUI

/// How reliably you turn up to what you agreed to.
///
/// Shown only to the person it describes. Whether a partner should see this is an open product
/// decision, not an oversight: inside a couple a reliability score is as usable as a weapon as it
/// is as a signal, and that question deserves a deliberate answer before anyone else can read it.
///
/// Says nothing at all until there is enough history to say it. A percentage next to one or two
/// plans is a number pretending to be a measurement.
struct ReliabilityCard: View {
    let score: ReliabilityScore

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.md) {
            Text("Turning up")
                .mgFont(.h2)

            if let percentage = score.percentage {
                earned(percentage)
            } else {
                notYet
            }
        }
    }

    private var notYet: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            Text("Not enough yet")
                .mgFont(.h3)
            Text("""
            Once you've been through a few plans together, this will show how often they \
            actually happen. \(ReliabilityScore.minimumSample - score.settledCount) to go.
            """)
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)
        }
        .mgSurfaceCard()
    }

    private func earned(_ percentage: Int) -> some View {
        VStack(alignment: .leading, spacing: MGSpacing.md) {
            HStack(spacing: MGSpacing.xl) {
                ZStack {
                    GrowthRing(progress: Double(percentage) / 100, size: 80, lineWidth: 9)
                    Text("\(percentage)%")
                        .mgFont(.h3)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("You turned up to \(percentage) percent of your plans")

                VStack(alignment: .leading, spacing: MGSpacing.xs) {
                    line("\(score.attended) went ahead", icon: "checkmark.circle")
                    if score.missed > 0 {
                        line("\(score.missed) didn't happen", icon: "xmark.circle")
                    }
                    if score.lateCancellations > 0 {
                        line(
                            "\(score.lateCancellations) cancelled late",
                            icon: "clock.badge.exclamationmark"
                        )
                    }
                }

                Spacer(minLength: 0)
            }

            // Named plainly rather than punitively. The point of surfacing a run of
            // cancellations is that the person notices it, not that they are told off.
            if score.isCancellingRepeatedly {
                Text("You've called off your last \(score.cancellationStreak) plans in a row.")
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)
            }
        }
        .mgSurfaceCard()
    }

    private func line(_ text: String, icon: String) -> some View {
        HStack(spacing: MGSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(MGColors.warm600)
            Text(text)
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)
        }
    }
}

#Preview("Earned") {
    ReliabilityCard(
        score: ReliabilityScore(
            attended: 11,
            missed: 1,
            lateCancellations: 2,
            cancellationStreak: 0
        )
    )
    .padding()
    .background(MGColors.sand)
}

#Preview("Not enough yet") {
    ReliabilityCard(
        score: ReliabilityScore(attended: 2, missed: 0, lateCancellations: 0, cancellationStreak: 0)
    )
    .padding()
    .background(MGColors.sand)
}
