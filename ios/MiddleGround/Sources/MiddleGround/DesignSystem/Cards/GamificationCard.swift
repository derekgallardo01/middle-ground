import SwiftUI

struct GamificationCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
            
            Text(value)
                .font(MGFonts.h2)
                .foregroundStyle(MGColors.slate)
            
            Text(title)
                .font(MGFonts.caption)
                .foregroundStyle(MGColors.warm600)
                .multilineTextAlignment(.center)
            
            if let subtitle {
                Text(subtitle)
                    .font(MGFonts.caption)
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: MGColors.slate.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}

struct GrowthRing: View {
    let progress: Double // 0...1
    let size: CGFloat
    let lineWidth: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(MGColors.warm200, lineWidth: lineWidth)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(MGColors.indigo, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: progress)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 12) {
        GamificationCard(title: "Daily Streak", value: "🔥 12", subtitle: "days", icon: "flame.fill", color: MGColors.coral)
        GamificationCard(title: "Growth Score", value: "85", subtitle: "Great job!", icon: "chart.line.uptrend.xyaxis", color: MGColors.indigo)
    }
    .padding()
    .background(MGColors.sand)
}
