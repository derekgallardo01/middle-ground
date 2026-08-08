import SwiftUI

/// The one plan that has gone quiet, surfaced at the top of the feed.
///
/// The failure this exists for is specific: a plan agreed three weeks out that nobody opens again
/// until it has already died. Putting it on the plan's own screen is not enough, because the whole
/// problem is that nobody goes back to look at it. So it comes to them.
///
/// Deliberately not a red banner. Nothing has gone wrong — a group has been busy, which is the
/// normal state of a group. It states what it noticed and offers the tap; it does not tell anybody
/// off, and the "leave it" is a real option rather than a snooze that asks again tomorrow.
struct QuietPlanCard: View {
    let title: String
    let reason: String
    let isSending: Bool
    let onOpen: () -> Void
    let onSayStillOn: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.md) {
            HStack(alignment: .top, spacing: MGSpacing.md) {
                Image(systemName: "wind")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MGColors.warm600)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .mgFont(.h3)
                        .lineLimit(2)
                    Text(reason)
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.warm600)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: MGSpacing.sm) {
                Button(action: onSayStillOn) {
                    Text("I'm still in")
                        .mgFont(.bodySmall, color: MGColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MGSpacing.sm)
                        .background(MGColors.teal)
                        .clipShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(isSending)
                .accessibilityIdentifier("quietPlanStillOn")

                Button(action: onOpen) {
                    Text("Open it")
                        .mgFont(.bodySmall, color: MGColors.slate)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MGSpacing.sm)
                        .background(MGColors.warm100)
                        .clipShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle())

                Button(action: onDismiss) {
                    Text("Leave it")
                        .mgFont(.bodySmall, color: MGColors.warm600)
                        .padding(.vertical, MGSpacing.sm)
                        .padding(.horizontal, MGSpacing.md)
                }
                .accessibilityIdentifier("quietPlanDismiss")
            }
        }
        .mgSurfaceCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) has gone quiet. \(reason)")
    }
}

#Preview {
    VStack(spacing: 20) {
        QuietPlanCard(
            title: "Weekend away?",
            reason: "Agreed 12 days ago. Nothing since. 8 days to go.",
            isSending: false,
            onOpen: {},
            onSayStillOn: {},
            onDismiss: {}
        )
        QuietPlanCard(
            title: "Gig on Saturday",
            reason: "Nothing said in 9 days, and it is 3 days away.",
            isSending: false,
            onOpen: {},
            onSayStillOn: {},
            onDismiss: {}
        )
    }
    .padding()
    .background(MGColors.sand)
}
