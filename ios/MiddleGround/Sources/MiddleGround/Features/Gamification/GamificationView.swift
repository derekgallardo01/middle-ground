import SwiftUI

struct GamificationView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var levelBadge: CGFloat = 80
    @ScaledMetric(relativeTo: .largeTitle) private var levelNumber: CGFloat = 32

    @State private var viewModel = GamificationViewModel()
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
                        levelHeader
                        statsRow
                        StreakView(days: viewModel.stats.streakDays, weekDays: viewModel.weeklyCompletion)
                        AchievementsView(achievements: viewModel.achievements)
                        ActivityFeedView(activities: viewModel.activities)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle("Activities")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await viewModel.loadGamificationData()
            }
        }
        .task {
            await viewModel.loadCurrentUser()
            await viewModel.loadGamificationData()
        }
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
                        .foregroundStyle(.white)
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
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MGColors.warm100)
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .mgShadow(MGShadow.md)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            GamificationCard(
                title: "Daily Streak",
                value: "🔥 \(viewModel.stats.streakDays)",
                subtitle: "days",
                icon: "flame.fill",
                color: MGColors.coral
            )
            GamificationCard(
                title: "Growth Score",
                value: "\(viewModel.stats.growthScore)",
                subtitle: "Great job!",
                icon: "chart.line.uptrend.xyaxis",
                color: MGColors.indigo
            )
        }
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return GamificationView()
}
