import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    /// Shows a spinner and blocks further taps while work is in flight.
    var isLoading: Bool = false
    let action: () -> Void
    var accessibilityLabel: String?

    /// Scales with the label. Fixed at 16 the icon stayed small while the text grew at
    /// accessibility sizes.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 16

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(MGColors.onAccent)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .semibold))
                }
                Text(title)
                    .mgFont(.body)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(MGColors.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(MGColors.indigo)
            .clipShape(Capsule())
            .shadow(color: MGColors.indigo.opacity(0.25), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isLoading)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.97 : 1.0))
            .opacity(reduceMotion ? 1.0 : (configuration.isPressed ? 0.9 : 1.0))
            .mgAnimation(MGMotion.tap, value: configuration.isPressed)
    }
}

struct GhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .mgFont(.body)
                .fontWeight(.semibold)
                .foregroundStyle(MGColors.slate)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .background(MGColors.warm100)
                .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "New Request", systemImage: "plus") {}
        GhostButton(title: "Maybe later") {}
    }
    .padding()
    .background(MGColors.sand)
}
