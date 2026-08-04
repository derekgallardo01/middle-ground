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
            if viewModel.transcript.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundStyle(MGColors.warm600)
                    Text("Nothing here yet")
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
                // Decisions and conversation interleaved by time. They are stored apart -- the
                // chain on the request document, messages in a subcollection -- for reasons no
                // reader of this screen should ever have to know about.
                VStack(alignment: .leading, spacing: MGSpacing.xl) {
                    ForEach(viewModel.transcript) { entry in
                        transcriptRow(entry)
                            // The chat surface had no motion at all: a reply simply existed,
                            // with nothing to show it had just arrived. Rising slightly as it
                            // fades in is what makes it read as *new* rather than as something
                            // that was always there.
                            .mgTransition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .mgAnimation(MGMotion.reveal, value: viewModel.transcript.count)
            }

            if let seenBy = viewModel.seenBySentence {
                Text(seenBy)
                    .mgFont(.caption)
                    .foregroundStyle(MGColors.warm400)
                    .padding(.horizontal, MGSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if !viewModel.typingNames.isEmpty {
                TypingIndicator(names: viewModel.typingNames)
                    .mgTransition(.opacity)
            }

            // Gated on being able to *speak*, not on whose turn it is. Gating the whole composer
            // on `canRespond` meant somebody who had already answered could not ask a question
            // about the plan they had just agreed to — and the only send path was a counter, so
            // asking one withdrew the agreement. Attaching a time is still an answer, so that
            // button keeps the narrower gate.
            if viewModel.canComment {
                VStack(alignment: .leading, spacing: MGSpacing.sm) {
                    if let time = viewModel.counterProposedTime {
                        attachedTime(time)
                    }

                    // Says what the next send will attach itself to. Without it, tapping Reply
                    // and then typing looks identical to writing a new line, and the reply lands
                    // somewhere the person did not expect.
                    if let replyingTo = viewModel.replyingTo {
                        HStack(spacing: MGSpacing.xs) {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(.caption)
                            Text("Replying to \(viewModel.name(for: replyingTo.senderID))")
                                .mgFont(.caption)
                            Spacer()
                            Button {
                                viewModel.replyingToID = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stop replying")
                        }
                        .foregroundStyle(MGColors.warm600)
                        .padding(.horizontal, MGSpacing.sm)
                    }

                    HStack(spacing: MGSpacing.md) {
                        // Attaching a time is what makes a counter actually move the plan.
                        // Without it "Sunday instead?" was only ever transcript text, so
                        // accepting the counter left the original date on the request and the
                        // Calendar entry on a day nobody agreed to.
                        if viewModel.canRespond {
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
                        }

                        TextField(
                            viewModel.canRespond ? "Say something, or suggest a time..." : "Say something...",
                            text: $viewModel.counterText,
                            axis: .vertical
                        )
                        // Throttled inside the view model to one write per heartbeat, not one
                        // per keystroke.
                        .onChange(of: viewModel.counterText) { _, _ in viewModel.noteTyping() }
                            .mgFont(.body)
                            .focused($composerFocused)
                            .submitLabel(.send)
                            .padding(12)
                            .background(MGColors.warm100)
                            .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))

                        Button {
                            Task { await viewModel.send() }
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
                        // The field sets `.submitLabel(.send)`, so the keyboard's return key is
                        // also called "Send" and a label query matches two elements. The
                        // identifier names this one unambiguously.
                        .accessibilityIdentifier("sendMessage")
                        .accessibilityHint("Sends what you wrote. With a time attached it suggests that time instead.")
                    }
                }
                .sheet(isPresented: $showTimePicker) { timePicker }
            }
        }
    }

    /// The time attached to the counter being written, with a way to take it back off.
    @ViewBuilder
    private func transcriptRow(_ entry: TranscriptEntry) -> some View {
        switch entry {
        case .decision(let message):
            NegotiationBubble(message: message, currentUserID: viewModel.currentUserID)
        case .message(let message):
            MessageBubble(
                message: message,
                senderName: viewModel.name(for: message.senderID),
                isMine: message.senderID == viewModel.currentUserID,
                replies: viewModel.replies(to: message.id),
                replyName: { viewModel.name(for: $0) },
                onReply: { viewModel.replyingToID = message.id }
            )
        }
    }

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
                    // Into `mgFont`, not after it — see `mgFont(_:color:)`. Applied afterwards
                    // it is dropped, and your own messages sit on an indigo fill.
                    Text(text)
                        .mgFont(.body, color: isCurrentUser ? MGColors.onAccent : MGColors.slate)
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
