import SwiftUI

/// What sits behind the two numbers on the Activities tab.
///
/// Both were previously unexplained: the app showed "Growth Score 40" with nothing anywhere
/// saying what produced it or how to move it, and a streak with no statement of what breaks it.
/// Every figure here is derived from data already stored on `GamificationStats`, so this reports
/// the real calculation rather than a description of one.
enum StatDetail: String, Identifiable {
    case streak
    case growth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .streak: return "Daily Streak"
        case .growth: return "Growth Score"
        }
    }
}

struct StatDetailView: View {
    let detail: StatDetail
    let stats: GamificationStats
    let weeklyCompletion: [Bool]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MGSpacing.xl) {
                    switch detail {
                    case .streak: streakBody
                    case .growth: growthBody
                    }
                }
                .padding(.horizontal, MGSpacing.lg)
                .mgReadableWidth()
                .padding(.vertical, MGSpacing.md)
            }
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle(detail.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Streak

    private var streakBody: some View {
        VStack(alignment: .leading, spacing: MGSpacing.xl) {
            StreakView(days: stats.streakDays, weekDays: weeklyCompletion)

            VStack(alignment: .leading, spacing: MGSpacing.sm) {
                Text(streakStatusTitle)
                    .mgFont(.h3)
                Text(streakStatusDetail)
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)
            }
            .mgSurfaceCard()

            explainer(
                "How it works",
                // Stated from the implementation in GamificationService.recordResponse, not from
                // a general idea of how streaks usually behave.
                [
                    "Respond to a request and today counts.",
                    "Respond again tomorrow and the streak grows.",
                    "More than one response in a day doesn't add another day.",
                    "Miss a whole day and it starts again at one."
                ]
            )
        }
    }

    /// Whether today is already covered, which is the only thing a streak owner actually wants
    /// to know when they open this.
    private var hasRespondedToday: Bool {
        guard let last = stats.lastResponseDate else { return false }
        return Calendar.current.isDateInToday(last)
    }

    private var streakStatusTitle: String {
        if stats.streakDays == 0 { return "Not started yet" }
        return hasRespondedToday ? "Safe for today" : "At risk today"
    }

    private var streakStatusDetail: String {
        guard stats.streakDays > 0 else {
            return "Respond to a request and your streak begins."
        }
        if hasRespondedToday {
            return "You've already responded today. Respond again tomorrow to make it "
                + "\(stats.streakDays + 1) days."
        }
        return "You haven't responded today. Respond before midnight to keep your "
            + "\(stats.streakDays)-day streak, or it starts again at one."
    }

    // MARK: - Growth

    private var growthBody: some View {
        VStack(alignment: .leading, spacing: MGSpacing.xl) {
            HStack(spacing: MGSpacing.xl) {
                ZStack {
                    // GrowthRing has existed unused since it was written; this is exactly the
                    // value it takes.
                    GrowthRing(progress: Double(stats.growthScore) / 100, size: 96, lineWidth: 10)
                    Text("\(stats.growthScore)")
                        .mgFont(.h1)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Growth score \(stats.growthScore) out of 100")

                VStack(alignment: .leading, spacing: MGSpacing.xs) {
                    Text("out of 100")
                        .mgFont(.body)
                        .foregroundStyle(MGColors.warm600)
                    Text(growthSummary)
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.warm600)
                }

                Spacer(minLength: 0)
            }
            .mgSurfaceCard()

            breakdown

            explainer(
                "Moving it",
                [
                    "Accepting is worth the most, three points each.",
                    "Finding a middle ground counts for two.",
                    "Every day of your streak adds one."
                ]
            )
        }
    }

    private var growthSummary: String {
        isCapped
            ? "You're at the maximum."
            : stats.growthScore == 0 ? "Nothing counted yet." : "Built from everything below."
    }

    /// The raw total before the cap. Showing a breakdown that sums past the number on the card
    /// would look like an arithmetic bug, so the cap is stated whenever it is doing something.
    private var rawTotal: Int {
        stats.acceptedCount * 3 + stats.negotiatedCount * 2 + stats.streakDays
    }

    private var isCapped: Bool { rawTotal > 100 }

    private var breakdown: some View {
        VStack(spacing: 0) {
            row("Accepted", count: stats.acceptedCount, multiplier: 3)
            Divider().overlay(MGColors.cardBorder)
            row("Middle ground found", count: stats.negotiatedCount, multiplier: 2)
            Divider().overlay(MGColors.cardBorder)
            row("Day streak", count: stats.streakDays, multiplier: 1)
            Divider().overlay(MGColors.cardBorder)

            HStack {
                Text(isCapped ? "Total (capped at 100)" : "Total")
                    .mgFont(.body)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(stats.growthScore)")
                    .mgFont(.body)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .padding(.vertical, MGSpacing.md)

            if isCapped {
                Text("Your activity adds up to \(rawTotal). The score stops at 100.")
                    .mgFont(.caption)
                    .foregroundStyle(MGColors.warm600)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, MGSpacing.lg)
        .padding(.vertical, MGSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(MGColors.surface)
        .mgCard()
        .mgShadow(MGShadow.md)
    }

    private func row(_ label: String, count: Int, multiplier: Int) -> some View {
        HStack {
            Text(label)
                .mgFont(.body)
            Spacer()
            Text("\(count) × \(multiplier)")
                .mgFont(.bodySmall)
                .monospacedDigit()
                .foregroundStyle(MGColors.warm600)
            Text("\(count * multiplier)")
                .mgFont(.body)
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.vertical, MGSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(count) at \(multiplier) points each, \(count * multiplier) points")
    }

    // MARK: - Shared

    private func explainer(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            Text(title)
                .mgFont(.h3)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: MGSpacing.sm) {
                    Text("•")
                    Text(line)
                }
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)
            }
        }
        .mgSurfaceCard()
    }
}

private let previewStats = GamificationStats(
    streakDays: 6,
    relationshipXP: 420,
    level: 1,
    growthScore: 41,
    nextLevelXP: 500,
    acceptedCount: 9,
    negotiatedCount: 4,
    lastResponseDate: Date()
)

#Preview("Streak") {
    StatDetailView(
        detail: .streak,
        stats: previewStats,
        weeklyCompletion: [true, true, false, true, true, true, false]
    )
}

#Preview("Growth") {
    StatDetailView(detail: .growth, stats: previewStats, weeklyCompletion: [])
}
