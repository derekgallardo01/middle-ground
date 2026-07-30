import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void
    var accessibilityLabel: String?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .mgFont(.body)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(MGColors.indigo)
            .clipShape(Capsule())
            .shadow(color: MGColors.indigo.opacity(0.25), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.97 : 1.0))
            .opacity(reduceMotion ? 1.0 : (configuration.isPressed ? 0.9 : 1.0))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
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
