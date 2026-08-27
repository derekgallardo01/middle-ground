import SwiftUI

/// Choosing what a plan looks like in the feed.
///
/// The first person to use this app said the feed "feels like a list", and he was describing a
/// column of identical white cards each carrying the same monochrome category glyph. The fix is
/// not to guess a better icon when a card is drawn — a guess made there is one nobody can
/// correct. It is to ask, once, here, where the person who knows what the evening is can answer.
///
/// It is never a blank choice. A face is already selected when this appears, seeded from the
/// category and replaced by any place that was picked, so sending without touching this still
/// produces something better than a heart on every plan.
///
/// A row rather than the system emoji keyboard on purpose. The keyboard offers several thousand
/// options for a decision worth about two seconds, and it cannot be reached without dismissing
/// the field above it. `PlaceSuggestion.forCategory` already knows what this category tends to
/// involve, and the last choice is always kept in the row so a venue's own emoji never vanishes
/// from a list it was never in.
struct PlanEmojiPicker: View {

    let choices: [String]
    let selected: String
    let onChoose: (String) -> Void

    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.xs) {
            Text("How it looks")
                .mgFont(.caption, color: MGColors.warm600)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MGSpacing.sm) {
                    ForEach(choices, id: \.self) { choice in
                        Button {
                            onChoose(choice)
                            Haptics.shared.impact(.light)
                        } label: {
                            Text(choice)
                                .font(.system(size: size))
                                .padding(MGSpacing.xs)
                                .background(
                                    Circle()
                                        .fill(choice == selected
                                              ? MGColors.indigo.opacity(0.18)
                                              : MGColors.warm100)
                                )
                                .overlay(
                                    Circle().stroke(
                                        MGColors.indigo.opacity(choice == selected ? 0.6 : 0),
                                        lineWidth: 2
                                    )
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                        // The emoji itself is not a label a screen reader can use — it would
                        // read "cocktail glass" with no hint of what tapping it does. Selection
                        // is a trait rather than a sentence, so VoiceOver announces it the way
                        // it announces every other selected control.
                        .accessibilityLabel("Plan icon")
                        .accessibilityValue(choice)
                        .accessibilityAddTraits(choice == selected ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        PlanEmojiPicker(choices: ["🍽️", "🍸", "🎬", "🌳", "❤️"], selected: "🍸") { _ in }
        PlanEmojiPicker(choices: ["🏠", "🍽️", "🌳"], selected: "🏠") { _ in }
    }
    .padding()
    .background(MGColors.sand)
}
