import SwiftUI

/// "Alex is typing…", and the animated dots that make it read as live.
///
/// Quiet on purpose. It sits directly above the composer, where the message it predicts will
/// appear, and it must not compete with the transcript for attention — it is the least important
/// thing on the screen and the most frequently changing.
///
/// Honours Reduce Motion through `mgAnimation`: with the setting on, the dots hold still and the
/// sentence carries it alone. A perpetual bouncing animation is exactly the kind of thing that
/// setting exists to stop.
struct TypingIndicator: View {
    let names: [String]

    @State private var phase = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: MGSpacing.xs) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(MGColors.warm400)
                        .frame(width: 5, height: 5)
                        .opacity(phase == index ? 1 : 0.35)
                }
            }
            .mgAnimation(MGMotion.reveal, value: phase)

            Text(sentence)
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm600)
        }
        .padding(.horizontal, MGSpacing.sm)
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sentence)
    }

    /// The verb has to agree, or the most ordinary case in a group reads as broken English.
    private var sentence: String {
        switch names.count {
        case 0: return ""
        case 1: return "\(names[0]) is typing"
        default: return "\(names.formatted(.list(type: .and))) are typing"
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        TypingIndicator(names: ["Alex"])
        TypingIndicator(names: ["Alex", "Sam"])
    }
    .padding()
}
