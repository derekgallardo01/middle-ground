import SwiftUI

struct AchievementsView: View {
    let achievements: [Achievement]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievements")
                .font(MGFonts.h2)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                ForEach(achievements) { achievement in
                    AchievementCell(achievement: achievement)
                }
            }
        }
    }
}

struct AchievementCell: View {
    let achievement: Achievement
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(achievement.isUnlocked ? MGColors.sunshine.opacity(0.2) : MGColors.warm100)
                    .frame(width: 64, height: 64)
                
                Image(systemName: achievement.iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(achievement.isUnlocked ? MGColors.sunshine : MGColors.warm400)
            }
            
            Text(achievement.title)
                .font(MGFonts.caption)
                .foregroundStyle(achievement.isUnlocked ? MGColors.slate : MGColors.warm400)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .opacity(achievement.isUnlocked ? 1.0 : 0.6)
    }
}

#Preview {
    AchievementsView(achievements: [
        Achievement.preview,
        Achievement(id: "ach_5", title: "Locked One", description: "", iconName: "star.fill", requiredValue: 100, unlockedAt: nil)
    ])
    .padding()
    .background(MGColors.sand)
}
