import SwiftUI

struct GamificationView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var levelBadge: CGFloat = 80
    @ScaledMetric(relativeTo: .largeTitle) private var levelNumber: CGFloat = 32

    @State private var viewModel = GamificationViewModel()
    @State private var selectedStat: StatDetail?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if viewModel.isLoading {
                        LoadingSkeleton(type: .gamification)
                    } else if let errorMessage = viewModel.errorMessage {
                        ErrorState(message: errorMessage) {
                            Task { await viewModel.loadGamificationData() }
                        }
                    } else {
                        if hasNoProgressYet { primer }
                        levelHeader
                        statsRow
                        StreakView(days: viewModel.stats.streakDays, weekDays: viewModel.weeklyCompletion)
                        CategoryLevelsView(stats: viewModel.stats)
                        AchievementsView(achievements: viewModel.achievements)
                        ActivityFeedView(activities: viewModel.activities)
                    }
                }
                .padding(.horizontal, 16)
                .mgReadableWidth()
                .padding(.vertical, 12)
            }
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle("Activities")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await viewModel.loadGamificationData()
            }
            .sheet(item: $selectedStat) { stat in
                StatDetailView(
                    detail: stat,
                    stats: viewModel.stats,
                    weeklyCompletion: viewModel.weeklyCompletion
                )
            }
        }
        .task {
            await viewModel.loadCurrentUser()
            await viewModel.loadGamificationData()
        }
    }

    /// Nothing earned yet — every number on this screen is a zero.
    private var hasNoProgressYet: Bool {
        viewModel.activities.isEmpty && viewModel.stats.relationshipXP == 0
    }

    /// Explains what the zeroes mean before showing a screenful of them.
    ///
    /// This tab is the most "gamified" surface in the app and was also the emptiest: Level 1,
    /// 0 / 500 XP, a 0-day streak asserting "you're building healthy habits together", seven
    /// blank day pills and three greyed-out badges — with nothing anywhere saying how any of
    /// it is earned. The chrome is worth keeping, because it shows what you are working
    /// towards; it just needed a sentence of context.
    private var primer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How this works")
                .mgFont(.h3)

            Text("""
            Responding to each other earns XP. Accepting is worth the most, and finding a \
            middle ground counts too — the point is turning up for each other, not agreeing \
            with everything.
            """)
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)

            HStack(spacing: 16) {
                ForEach([ResponseType.accept, .negotiate, .reschedule], id: \.self) { type in
                    HStack(spacing: 5) {
                        Text(type.emoji)
                        Text("+\(GamificationRules.xp(for: type))")
                            .mgFont(.caption)
                            .monospacedDigit()
                            .foregroundStyle(MGColors.warm600)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(type.displayName) earns \(GamificationRules.xp(for: type)) XP")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
    }

    private var levelHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(MGColors.middleGradient)
                        .frame(width: levelBadge, height: levelBadge)

                    Text("\(viewModel.stats.level)")
                        .font(.system(size: levelNumber, weight: .bold, design: .rounded))
                        .foregroundStyle(MGColors.onAccent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Level \(viewModel.stats.level)")
                        .mgFont(.h1)
                    Text("\(viewModel.stats.relationshipXP) / \(viewModel.stats.nextLevelXP) XP")
                        .mgFont(.body)
                        .foregroundStyle(MGColors.warm600)
                }

                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: MGRadius.sm, style: .continuous)
                        .fill(MGColors.warm100)
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: MGRadius.sm, style: .continuous)
                        .fill(MGColors.middleGradient)
                        .frame(
                            width: geo.size.width * viewModel.progressToNextLevel,
                            height: 12
                        )
                        .animation(
                            reduceMotion ? nil : MGMotion.expressive,
                            value: viewModel.progressToNextLevel
                        )
                }
            }
            .frame(height: 12)
        }
        .padding(20)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
        .mgShadow(MGShadow.md)
    }

    /// Both cards open a sheet explaining where their number came from.
    ///
    /// `Button` rather than `.onTapGesture`, so the button trait reaches VoiceOver — a tap
    /// gesture announces these as plain text and gives no indication they do anything.
    private var statsRow: some View {
        HStack(spacing: 12) {
            Button {
                selectedStat = .streak
            } label: {
                GamificationCard(
                    title: "Daily Streak",
                    value: "\(viewModel.stats.streakDays)",
                    subtitle: viewModel.stats.streakDays == 1 ? "day" : "days",
                    icon: "flame.fill",
                    color: MGColors.coral
                )
            }
            .accessibilityHint("Shows how your streak works and whether today counts")

            Button {
                selectedStat = .growth
            } label: {
                GamificationCard(
                    title: "Growth Score",
                    value: "\(viewModel.stats.growthScore)",
                    subtitle: viewModel.stats.growthScore > 0 ? "Great job!" : "Just getting started",
                    icon: "chart.line.uptrend.xyaxis",
                    color: MGColors.indigo
                )
            }
            .accessibilityHint("Shows how your score was calculated")
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return GamificationView()
}
