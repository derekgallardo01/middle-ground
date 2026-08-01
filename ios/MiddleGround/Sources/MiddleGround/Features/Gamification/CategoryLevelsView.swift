import SwiftUI

/// Per-category progression: what a pair actually spends time on, rather than one undifferentiated
/// XP total.
///
/// Only categories with progress appear. A grid of eight zeroes says nothing, and the empty state
/// below is a clearer thing to show someone who has not started.
struct CategoryLevelsView: View {
    let stats: GamificationStats

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.md) {
            Text("What you do together")
                .mgFont(.h2)

            if stats.rankedCategories.isEmpty {
                Text("Respond to requests and the things you do most will show up here.")
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mgSurfaceCard()
            } else {
                VStack(spacing: MGSpacing.md) {
                    ForEach(stats.rankedCategories, id: \.category) { entry in
                        row(category: entry.category, xp: entry.xp)
                    }
                }
                .mgSurfaceCard()
            }
        }
    }

    private func row(category: RequestCategory, xp: Int) -> some View {
        let level = GamificationRules.level(forXP: xp)
        // Progress through the current level, not toward the next from zero — otherwise a bar
        // resets to empty the instant someone levels up, which reads as losing progress.
        let floorXP = (level - 1) * GamificationRules.xpPerLevel
        let progress = Double(xp - floorXP) / Double(GamificationRules.xpPerLevel)

        return VStack(alignment: .leading, spacing: MGSpacing.xs) {
            HStack(spacing: MGSpacing.sm) {
                Image(systemName: category.iconName)
                    .foregroundStyle(MGColors.indigo)
                    .frame(width: 24)
                Text(category.displayName)
                    .mgFont(.body)
                Spacer()
                Text("Level \(level)")
                    .mgFont(.bodySmall)
                    .monospacedDigit()
                    .foregroundStyle(MGColors.warm600)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MGColors.warm100)
                    Capsule()
                        .fill(MGColors.middleGradient)
                        .frame(width: geo.size.width * min(max(progress, 0), 1))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.displayName), level \(level), \(xp) XP")
    }
}

#Preview {
    CategoryLevelsView(
        stats: GamificationStats(
            streakDays: 4,
            relationshipXP: 900,
            level: 2,
            growthScore: 40,
            nextLevelXP: 1000,
            categoryXP: ["chill": 620, "dating": 275, "travel": 90]
        )
    )
    .padding()
    .background(MGColors.sand)
}
