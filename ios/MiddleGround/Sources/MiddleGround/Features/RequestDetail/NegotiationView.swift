import SwiftUI

struct NegotiationView: View {
    @ScaledMetric(relativeTo: .body) private var sendButton: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var sendGlyph: CGFloat = 18

    @Bindable var viewModel: RequestDetailViewModel

    /// Owned by `RequestDetailView` so the Negotiate button — which sits above this view — can
    /// put the cursor in the field rather than sending an empty response.
    @FocusState.Binding var composerFocused: Bool

    @State private var showTimePicker = false
    @State private var pickedTime = Date()

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
                // Each bubble carries a caption underneath it ("Countered", "Accepted") set 4pt
                // below the bubble it describes. At 12pt between messages the caption sat
                // almost as close to the *next* bubble as to its own, so a reply and the label
                // above it read as one unit. The gap between turns has to clearly beat the gap
                // within one.
                VStack(alignment: .leading, spacing: MGSpacing.xl) {
                    ForEach(viewModel.request.negotiationChain) { message in
                        NegotiationBubble(message: message, currentUserID: viewModel.currentUserID)
                    }
                }
            }

            // Gated on whose turn it is, not merely on the request being open. Gating on
            // `isPending` alone showed the creator an enabled composer on their own unanswered
            // request; sending hit `guard canRespond` in RequestService and surfaced as a
            // generic "Failed to send response." — a guaranteed failure presented as an error.
            if viewModel.canRespond {
                VStack(alignment: .leading, spacing: MGSpacing.sm) {
                    if let time = viewModel.counterProposedTime {
                        attachedTime(time)
                    }

                    HStack(spacing: MGSpacing.md) {
                        // Attaching a time is what makes a counter actually move the plan.
                        // Without it "Sunday instead?" was only ever transcript text, so
                        // accepting the counter left the original date on the request and the
                        // Calendar entry on a day nobody agreed to.
                        Button {
                            pickedTime = viewModel.counterProposedTime
                                ?? viewModel.request.proposedTime
                                ?? Date().addingTimeInterval(3600)
                            showTimePicker = true
                        } label: {
                            Image(systemName: viewModel.counterProposedTime == nil
                                  ? "calendar.badge.plus" : "calendar.badge.checkmark")
                                .font(.system(size: sendGlyph, weight: .semibold))
                                .foregroundStyle(MGColors.indigo)
                                .frame(width: sendButton, height: sendButton)
                                .background(MGColors.warm100)
                                .clipShape(Circle())
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .accessibilityLabel(viewModel.counterProposedTime == nil
                                            ? "Suggest a time" : "Change the suggested time")
                        .accessibilityHint("Attaches a new time to your suggestion")

                        TextField("Suggest another time or idea...", text: $viewModel.counterText, axis: .vertical)
                            .mgFont(.body)
                            .focused($composerFocused)
                            .submitLabel(.send)
                            .padding(12)
                            .background(MGColors.warm100)
                            .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))

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
                            .background(viewModel.canSendCounter ? MGColors.indigo : MGColors.warm400)
                            .clipShape(Circle())
                        }
                        .disabled(!viewModel.canSendCounter || viewModel.isSending)
                        .buttonStyle(ScaleButtonStyle())
                        // Announced as "arrow up, button" without this — and it is the only way to
                        // send a counter.
                        .accessibilityLabel("Send")
                        .accessibilityHint("Sends your suggestion to the other person")
                    }
                }
                .sheet(isPresented: $showTimePicker) { timePicker }
            }
        }
    }

    /// The time attached to the counter being written, with a way to take it back off.
    private func attachedTime(_ time: Date) -> some View {
        HStack(spacing: MGSpacing.sm) {
            Image(systemName: "clock")
            Text(time.formatted(date: .abbreviated, time: .shortened))
                .mgFont(.bodySmall)
            Button {
                viewModel.counterProposedTime = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .accessibilityLabel("Remove the suggested time")
        }
        .foregroundStyle(MGColors.indigo)
        .padding(.vertical, MGSpacing.sm)
        .padding(.horizontal, MGSpacing.md)
        .background(MGColors.indigo.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggesting \(time.formatted(date: .abbreviated, time: .shortened))")
    }

    private var timePicker: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: MGSpacing.xl) {
                Text("Suggest a different time. Accepting your suggestion moves the plan to it.")
                    .mgFont(.body)
                    .foregroundStyle(MGColors.warm600)

                DatePicker("New time", selection: $pickedTime, in: Date()...)
                    .datePickerStyle(.graphical)
                    .tint(MGColors.indigo)

                Spacer()
            }
            .padding()
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle("Suggest a time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTimePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attach") {
                        viewModel.counterProposedTime = pickedTime
                        showTimePicker = false
                        composerFocused = true
                    }
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

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: MGSpacing.xs) {
                if let text = message.text, !text.isEmpty {
                    Text(text)
                        .mgFont(.body)
                        .foregroundStyle(isCurrentUser ? MGColors.onAccent : MGColors.slate)
                        .padding(.vertical, MGSpacing.md)
                        .padding(.horizontal, MGSpacing.lg)
                        .background(isCurrentUser ? MGColors.indigo : MGColors.warm100)
                        .clipShape(RoundedRectangle(
                            cornerRadius: MGRadius.md,
                            style: .continuous
                        ))
                }

                HStack(spacing: MGSpacing.xs) {
                    Text(message.responseType.emoji)
                    Text(message.responseType.displayName)
                        .mgFont(.caption)
                        .foregroundStyle(MGColors.warm600)
                }
            }
            // Reads as one turn, so VoiceOver does not announce the text and its label as two
            // unrelated items.
            .accessibilityElement(children: .combine)

            if !isCurrentUser { Spacer(minLength: 40) }
        }
    }
}

#Preview {
    @Previewable @FocusState var focused: Bool
    AppConfiguration.useMockRepositories = true
    return NegotiationView(
        viewModel: RequestDetailViewModel(request: .previewNegotiating),
        composerFocused: $focused
    )
    .padding()
    .background(MGColors.sand)
}
