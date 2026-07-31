import SwiftUI

struct LoadingSkeleton: View {
    enum SkeletonType {
        case list
        case calendar
        case gamification
    }

    let type: SkeletonType
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            switch type {
            case .list:
                listSkeleton
            case .calendar:
                calendarSkeleton
            case .gamification:
                gamificationSkeleton
            }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: true)) {
                    isAnimating.toggle()
                }
            }
        }
    }

    // Radii match the cards each skeleton stands in for. They previously did not — the list
    // skeleton used 12 against RequestCard's 20, calendar 16 against the grid's 24, and
    // gamification 20 against GamificationCard's 24 — so every screen popped its corners at
    // the moment the real content arrived.
    private var listSkeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous)
                    .fill(placeholderColor)
                    .frame(height: 120)
            }
        }
    }

    private var calendarSkeleton: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous)
                .fill(placeholderColor)
                .frame(height: 320)

            RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous)
                .fill(placeholderColor)
                .frame(height: 140)
        }
    }

    private var gamificationSkeleton: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous)
                .fill(placeholderColor)
                .frame(height: 180)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous)
                    .fill(placeholderColor)
                    .frame(height: 120)

                RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous)
                    .fill(placeholderColor)
                    .frame(height: 120)
            }

            RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous)
                .fill(placeholderColor)
                .frame(height: 200)
        }
    }

    private var placeholderColor: some ShapeStyle {
        reduceMotion
            ? MGColors.warm100
            : MGColors.warm100.opacity(isAnimating ? 0.6 : 1.0)
    }
}

#Preview {
    LoadingSkeleton(type: .list)
        .padding()
        .background(MGColors.sand)
}
