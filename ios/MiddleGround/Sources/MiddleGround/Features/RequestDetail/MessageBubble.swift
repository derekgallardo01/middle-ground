import SwiftUI

/// A line of conversation, and anything said in reply to it.
///
/// Styled deliberately quieter than `NegotiationBubble`. A decision and a remark are not the same
/// weight of thing, and if they look identical the transcript stops showing at a glance where the
/// plan actually stands — which is the whole reason this app exists rather than a group chat.
///
/// Replies are nested under their parent rather than laid out inline. Threading conversation and
/// not decisions is the point: a plan has one decision to make, and letting *that* fork is how a
/// thread loses the plot.
struct MessageBubble: View {
    let message: PlanMessage
    let senderName: String
    let isMine: Bool
    let replies: [PlanMessage]
    /// Resolves a display name for a reply's sender.
    let replyName: (String) -> String
    let onReply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.xs) {
            line(text: message.text, sender: senderName, mine: isMine, at: message.at)

            if !replies.isEmpty {
                VStack(alignment: .leading, spacing: MGSpacing.xs) {
                    ForEach(replies) { reply in
                        line(
                            text: reply.text,
                            sender: replyName(reply.senderID),
                            mine: reply.senderID == message.senderID && isMine,
                            at: reply.at
                        )
                    }
                }
                // The indent is the thread. A rule down the left says "these belong to the line
                // above" without a disclosure control to tap or a count to reconcile.
                .padding(.leading, MGSpacing.md)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(MGColors.warm200)
                        .frame(width: 2)
                }
            }

            Button("Reply", action: onReply)
                .mgFont(.caption)
                .foregroundStyle(MGColors.indigo)
                .buttonStyle(.plain)
                .accessibilityHint("Replies to \(senderName)'s message")
        }
    }

    private func line(text: String, sender: String, mine: Bool, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: MGSpacing.xs) {
                Text(sender)
                    .mgFont(.caption)
                    .foregroundStyle(MGColors.warm600)
                Text(date.formatted(date: .omitted, time: .shortened))
                    .mgFont(.caption)
                    .foregroundStyle(MGColors.warm400)
            }
            Text(text)
                .mgFont(.body)
                .foregroundStyle(MGColors.slate)
                .padding(.vertical, MGSpacing.sm)
                .padding(.horizontal, MGSpacing.md)
                .background(mine ? MGColors.warm100 : MGColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous)
                        .stroke(MGColors.warm200, lineWidth: mine ? 0 : 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sender): \(text)")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        MessageBubble(
            message: PlanMessage(senderID: "a", text: "Which entrance are we meeting at?"),
            senderName: "Alex",
            isMine: false,
            replies: [
                PlanMessage(senderID: "b", text: "The one on Fourth", parentID: "x"),
                PlanMessage(senderID: "c", text: "Perfect, see you there", parentID: "x")
            ],
            replyName: { $0 == "b" ? "You" : "Sam" },
            onReply: {}
        )
        MessageBubble(
            message: PlanMessage(senderID: "b", text: "Running about ten minutes late"),
            senderName: "You",
            isMine: true,
            replies: [],
            replyName: { _ in "" },
            onReply: {}
        )
    }
    .padding()
}
