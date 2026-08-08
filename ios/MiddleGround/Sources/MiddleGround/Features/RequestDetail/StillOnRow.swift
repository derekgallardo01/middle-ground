import SwiftUI

/// "This has gone quiet — still on?"
///
/// The one tap that breaks a silence nobody wants to be the first to break. In a group of five,
/// everybody waits for somebody else to ask; this asks on their behalf, and shows the answers so
/// the asking only has to happen once.
///
/// It always says *why* it is here. A prompt that appears without explanation reads as the app
/// nagging; the sentence turns it into an observation somebody can disagree with — "agreed twelve
/// days ago, nothing since, eight days to go" is checkable.
struct StillOnRow: View {
    let reason: String
    let hasAnswered: Bool
    let stillOnNames: [String]
    let notYetNames: [String]
    let isSending: Bool
    let onSayStillOn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.md) {
            Label {
                Text("This has gone quiet")
                    .mgFont(.h3)
            } icon: {
                Image(systemName: "wind")
                    .foregroundStyle(MGColors.warm600)
            }

            Text(reason)
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)
                .fixedSize(horizontal: false, vertical: true)

            if hasAnswered {
                // Nothing to tap. Leaving an enabled button that re-sends the same answer invites
                // somebody to press it twice and wonder which one counted.
                Label {
                    Text("You said you're still in")
                        .mgFont(.bodySmall)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MGColors.teal)
                }
            } else {
                Button(action: onSayStillOn) {
                    Label("I'm still in", systemImage: "hand.raised.fill")
                        .mgFont(.body, color: MGColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MGSpacing.md)
                        .background(MGColors.teal)
                        .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(isSending)
                .accessibilityIdentifier("sayStillOn")
            }

            answers
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var answers: some View {
        VStack(alignment: .leading, spacing: MGSpacing.xs) {
            if !stillOnNames.isEmpty {
                Label {
                    Text(inLine)
                        .mgFont(.bodySmall)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MGColors.teal)
                }
            }

            if !notYetNames.isEmpty {
                Label {
                    // "Not heard from" rather than "waiting on": the second makes somebody late
                    // for something they were never told about.
                    Text("Not heard from \(notYetNames.formatted(.list(type: .and))) yet")
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.warm600)
                } icon: {
                    Image(systemName: "clock")
                        .foregroundStyle(MGColors.warm600)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The verb has to agree, or it reads as broken English on exactly the plans this is for.
    private var inLine: String {
        let names = stillOnNames.formatted(.list(type: .and))
        return stillOnNames.count == 1 ? "\(names) is still in" : "\(names) are still in"
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        StillOnRow(
            reason: "Agreed 12 days ago. Nothing since. 8 days to go.",
            hasAnswered: false,
            stillOnNames: [],
            notYetNames: ["You", "Priya", "Sam"],
            isSending: false
        ) {}
        StillOnRow(
            reason: "Nothing said in 9 days, and it is 3 days away.",
            hasAnswered: true,
            stillOnNames: ["You", "Sam"],
            notYetNames: ["Priya"],
            isSending: false
        ) {}
    }
    .padding()
    .background(MGColors.sand)
}
