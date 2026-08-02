import SwiftUI

/// One response option.
///
/// Emphasis is deliberate rather than uniform. Every option used to render identically — same
/// tinted fill, same weight, same width — so a row of four gave the eye nowhere to land, and
/// Accept carried exactly as much visual pull as Decline. `prominent` marks the action we
/// expect and want to be easy; `quiet` demotes the destructive one so it is available without
/// being inviting.
struct ResponseButton: View {
    enum Emphasis {
        /// Filled. The expected action.
        case prominent
        /// Tinted. A normal alternative.
        case standard
        /// Text-weight. Available, not encouraged.
        case quiet
    }

    let type: ResponseType
    var emphasis: Emphasis = .standard
    var isBusy: Bool = false
    let action: () -> Void

    private var fill: Color {
        switch emphasis {
        case .prominent: return type.color
        case .standard:  return type.color.opacity(0.1)
        case .quiet:     return .clear
        }
    }

    private var foreground: Color {
        emphasis == .prominent ? MGColors.onAccent : type.color
    }

    private var strokeOpacity: Double {
        switch emphasis {
        case .prominent: return 0
        case .standard:  return 0.2
        case .quiet:     return 0.35
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // A spinner in place of the glyph, so the button keeps its size and the row
                // does not reflow mid-tap. Without any in-flight state a slow response was
                // indistinguishable from a dead tap, and the button stayed tappable.
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foreground)
                        .frame(height: emojiSize)
                } else {
                    Text(type.emoji)
                        .font(.system(size: emojiSize))
                }
                Text(type.displayName)
                    .mgFont(.caption)
                    .foregroundStyle(foreground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous)
                    .stroke(type.color.opacity(strokeOpacity), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isBusy)
        .accessibilityLabel("\(type.displayName) request")
        .accessibilityHint("Double tap to \(type.displayName.lowercased()) this request")
        .accessibilityAddTraits(emphasis == .prominent ? [.isButton] : [])
    }

    @ScaledMetric(relativeTo: .title3) private var emojiSize: CGFloat = 22
}

#Preview {
    HStack(spacing: 12) {
        ResponseButton(type: .accept, emphasis: .prominent) {}
        ResponseButton(type: .negotiate) {}
        ResponseButton(type: .decline, emphasis: .quiet) {}
    }
    .padding()
    .background(MGColors.sand)
}
