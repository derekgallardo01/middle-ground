import SwiftUI

struct GamificationView: View {
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
                        StreakView(days: viewModel.stats.streakDays)
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
                        .frame(width: 80, height: 80)
                    
                    Text("\(viewModel.stats.level)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Level \(viewModel.stats.level)")
                        .font(MGFonts.h1)
                    Text("\(viewModel.stats.relationshipXP) / \(viewModel.stats.nextLevelXP) XP")
                        .font(MGFonts.body)
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
                        .frame(width: geo.size.width * viewModel.progressToNextLevel, height: 12)
                        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.7), value: viewModel.progressToNextLevel)
                }
            }
            .frame(height: 12)
        }
        .padding(20)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: MGColors.slate.opacity(0.05), radius: 12, x: 0, y: 4)
    }
    
    private var statsRow: some View {
        HStack(spacing: 12) {
            GamificationCard(title: "Daily Streak", value: "🔥 \(viewModel.stats.streakDays)", subtitle: "days", icon: "flame.fill", color: MGColors.coral)
            GamificationCard(title: "Growth Score", value: "\(viewModel.stats.growthScore)", subtitle: "Great job!", icon: "chart.line.uptrend.xyaxis", color: MGColors.indigo)
        }
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return GamificationView()
}
