import SwiftUI

struct NegotiationView: View {
    @ScaledMetric(relativeTo: .body) private var sendButton: CGFloat = 44

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

            if viewModel.request.isPending {
                HStack(spacing: 12) {
                    TextField("Suggest another time or idea...", text: $viewModel.counterText, axis: .vertical)
                        .mgFont(.body)
                        .padding(12)
                        .background(MGColors.warm100)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        Task { await viewModel.sendCounter() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: sendButton, height: sendButton)
                            .background(viewModel.isCounterEmpty ? MGColors.warm400 : MGColors.indigo)
                            .clipShape(Circle())
                    }
                    .disabled(viewModel.isCounterEmpty || viewModel.isSending)
                    .buttonStyle(ScaleButtonStyle())
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
                        .foregroundStyle(isCurrentUser ? .white : MGColors.slate)
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
