import SwiftUI

/// Whether a group is still a group.
///
/// `FollowThroughCard` beside this answers "do the plans we agree to happen". This answers the
/// slower question underneath: **are we still doing anything together at all.** A group can have
/// flawless follow-through and be dead, because it has agreed to nothing since March.
///
/// Never a bare ring. `ROADMAP.md` settled that an unexplainable score is not worth showing — a
/// dial on its own tells somebody they are failing without telling them at what — so the sentence
/// underneath is the point and the ring is the decoration.
///
/// Shown for couples too, on the same reasoning as `FollowThroughCard`: nothing here is
/// per-person, and there is no arrangement of it that says which of you is the problem.
struct GroupEnergyCard: View {
    let groupName: String
    let energy: GroupEnergy

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            Text(groupName)
                .mgFont(.h3)

            if let progress = energy.ringProgress {
                measured(progress)
            } else {
                notYet
            }
        }
        .mgSurfaceCard()
    }

    /// An absence of evidence, said as one. A new group scored "cooling" would be told off for
    /// having just formed.
    private var notYet: some View {
        Text(energy.reason)
            .mgFont(.bodySmall)
            .foregroundStyle(MGColors.warm600)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func measured(_ progress: Double) -> some View {
        HStack(spacing: MGSpacing.xl) {
            ZStack {
                GrowthRing(progress: progress, size: 72, lineWidth: 8)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MGColors.indigo)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(groupName): \(label). \(energy.reason)")

            VStack(alignment: .leading, spacing: MGSpacing.xs) {
                Text(label)
                    .mgFont(.body)
                Text(energy.reason)
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    /// One word for the level. Warm rather than "100%" — this is not a percentage of anything, and
    /// dressing a judgement as arithmetic claims a precision it does not have.
    private var label: String {
        switch energy.level {
        case .notEnoughYet: return "Nothing to go on yet"
        case .cooling: return "Cooling off"
        case .steady: return "Ticking over"
        case .warm: return "Going strong"
        }
    }

    private var icon: String {
        switch energy.level {
        case .notEnoughYet: return "questionmark"
        case .cooling: return "wind"
        case .steady: return "figure.walk"
        case .warm: return "flame.fill"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        GroupEnergyCard(
            groupName: "Sunday hikers",
            energy: GroupEnergy(
                level: .warm,
                reason: "Last got together 6 days ago. One plan coming up.",
                daysSinceTogether: 6,
                upcomingCount: 1
            )
        )
        GroupEnergyCard(
            groupName: "Book club",
            energy: GroupEnergy(
                level: .cooling,
                reason: "Last got together 4 months ago. Nothing in the diary.",
                daysSinceTogether: 120,
                upcomingCount: 0
            )
        )
        GroupEnergyCard(
            groupName: "New group",
            energy: GroupEnergy(
                level: .notEnoughYet,
                reason: "Nothing to go on yet — make a plan and this fills in.",
                daysSinceTogether: nil,
                upcomingCount: 0
            )
        )
    }
    .padding()
    .background(MGColors.sand)
}
