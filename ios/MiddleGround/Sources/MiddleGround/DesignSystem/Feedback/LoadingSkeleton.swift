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

    private var listSkeleton: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(placeholderColor)
                .frame(height: 120)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(placeholderColor)
                .frame(height: 120)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(placeholderColor)
                .frame(height: 120)
        }
    }

    private var calendarSkeleton: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(placeholderColor)
                .frame(height: 320)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(placeholderColor)
                .frame(height: 140)
        }
    }

    private var gamificationSkeleton: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(placeholderColor)
                .frame(height: 180)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(placeholderColor)
                    .frame(height: 120)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(placeholderColor)
                    .frame(height: 120)
            }

            RoundedRectangle(cornerRadius: 20, style: .continuous)
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
