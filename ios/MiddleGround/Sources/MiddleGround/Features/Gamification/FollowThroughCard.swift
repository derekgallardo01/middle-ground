import SwiftUI

/// How often this group's plans actually happen.
///
/// The app's premise, said back to the people it is about. `ReliabilityCard` next to this one
/// answers "do *I* turn up"; this answers "do *we* make things happen", which is the question the
/// product exists to change the answer to.
///
/// Shown for every group, couples included — see `GroupFollowThrough` for why that does not
/// break the rule that couples are never scored. Nothing here is per-person, and there is no
/// arrangement of this card that tells you which of you is the problem.
struct FollowThroughCard: View {
    let groupName: String
    let followThrough: GroupFollowThrough

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            Text(groupName)
                .mgFont(.h3)

            if let percentage = followThrough.percentage {
                earned(percentage)
            } else {
                notYet
            }
        }
        .mgSurfaceCard()
    }

    private var notYet: some View {
        Text("""
        Once you've been through a few plans, this will show how many of them actually \
        happened. \(followThrough.plansUntilShown) to go.
        """)
            .mgFont(.bodySmall)
            .foregroundStyle(MGColors.warm600)
    }

    private func earned(_ percentage: Int) -> some View {
        HStack(spacing: MGSpacing.xl) {
            ZStack {
                GrowthRing(progress: Double(percentage) / 100, size: 72, lineWidth: 8)
                Text("\(percentage)%")
                    .mgFont(.h3)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(percentage) percent of plans with \(groupName) happened")

            VStack(alignment: .leading, spacing: MGSpacing.xs) {
                line("\(followThrough.happened) happened", icon: "checkmark.circle")
                if followThrough.fellThrough > 0 {
                    line("\(followThrough.fellThrough) fell through", icon: "xmark.circle")
                }
            }

            Spacer(minLength: 0)
        }
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

#Preview {
    VStack(spacing: MGSpacing.md) {
        FollowThroughCard(
            groupName: "Sunday hikers",
            followThrough: GroupFollowThrough(happened: 7, fellThrough: 3)
        )
        FollowThroughCard(
            groupName: "You and Sam",
            followThrough: GroupFollowThrough(happened: 1, fellThrough: 1)
        )
    }
    .padding()
    .background(MGColors.sand)
}
