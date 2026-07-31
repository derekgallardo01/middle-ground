import SwiftUI

struct NegotiationView: View {
    @ScaledMetric(relativeTo: .body) private var sendButton: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var sendGlyph: CGFloat = 18

    @Bindable var viewModel: RequestDetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.request.negotiationChain.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundStyle(MGColors.warm600)
                    Text("No responses yet")
                        .mgFont(.body)
                        .foregroundStyle(MGColors.warm600)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.request.negotiationChain) { message in
                        NegotiationBubble(message: message, currentUserID: viewModel.currentUser?.id)
                    }
                }
            }

            // Gated on whose turn it is, not merely on the request being open. Gating on
            // `isPending` alone showed the creator an enabled composer on their own unanswered
            // request; sending hit `guard canRespond` in RequestService and surfaced as a
            // generic "Failed to send response." — a guaranteed failure presented as an error.
            if viewModel.canRespond {
                HStack(spacing: 12) {
                    TextField("Suggest another time or idea...", text: $viewModel.counterText, axis: .vertical)
                        .mgFont(.body)
                        .padding(12)
                        .background(MGColors.warm100)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        Task { await viewModel.sendCounter() }
                    } label: {
                        Group {
                            if viewModel.isSending {
                                ProgressView().controlSize(.small).tint(MGColors.onAccent)
                            } else {
                                Image(systemName: "arrow.up")
                                    // Scales with the button, which is already @ScaledMetric.
                                    // Fixed at 18pt the glyph stayed put while the circle grew.
                                    .font(.system(size: sendGlyph, weight: .semibold))
                            }
                        }
                        .foregroundStyle(MGColors.onAccent)
                        .frame(width: sendButton, height: sendButton)
                        .background(viewModel.isCounterEmpty ? MGColors.warm400 : MGColors.indigo)
                        .clipShape(Circle())
                    }
                    .disabled(viewModel.isCounterEmpty || viewModel.isSending)
                    .buttonStyle(ScaleButtonStyle())
                    // Announced as "arrow up, button" without this — and it is the only way to
                    // send a counter.
                    .accessibilityLabel("Send")
                    .accessibilityHint("Sends your suggestion to the other person")
                }
            }
        }
    }
}

struct NegotiationBubble: View {
    let message: NegotiationMessage
    let currentUserID: String?

    private var isCurrentUser: Bool {
        message.senderID == currentUserID
    }

    var body: some View {
        HStack {
            if isCurrentUser { Spacer(minLength: 40) }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if let text = message.text, !text.isEmpty {
                    Text(text)
                        .mgFont(.body)
                        .foregroundStyle(isCurrentUser ? MGColors.onAccent : MGColors.slate)
                        .padding(12)
                        .background(isCurrentUser ? MGColors.indigo : MGColors.warm100)
                        .clipShape(RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        ))
                }

                HStack(spacing: 4) {
                    Text(message.responseType.emoji)
                    Text(message.responseType.displayName)
                        .mgFont(.caption)
                        .foregroundStyle(MGColors.warm600)
                }
            }

            if !isCurrentUser { Spacer(minLength: 40) }
        }
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return NegotiationView(viewModel: RequestDetailViewModel(request: .previewNegotiating))
        .padding()
        .background(MGColors.sand)
}
