import SwiftUI

struct GamificationCard: View {
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 24

    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            // Label first, then the number with its unit inline — per brand/preview.html.
            // Previously the value sat above an unlabelled caption, and the unit was painted
            // in the accent colour, which made "days" read as a tappable link.
            Text(title)
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm600)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(color)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .mgFont(.h2)
                    .foregroundStyle(MGColors.slate)
                if let subtitle {
                    Text(subtitle)
                        .mgFont(.caption)
                        .foregroundStyle(MGColors.warm600)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(MGColors.surface)
        .mgCard()
        .mgShadow(MGShadow.md)
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
        GamificationCard(
            title: "Growth Score",
            value: "85",
            subtitle: "Great job!",
            icon: "chart.line.uptrend.xyaxis",
            color: MGColors.indigo
        )
    }
    .padding()
    .background(MGColors.sand)
}
