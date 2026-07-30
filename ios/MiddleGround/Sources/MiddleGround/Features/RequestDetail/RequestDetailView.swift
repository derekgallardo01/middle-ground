import SwiftUI

struct RequestDetailView: View {
    @State private var viewModel: RequestDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCancelConfirmation = false
    var namespace: Namespace.ID

    init(request: Request, namespace: Namespace.ID) {
        _viewModel = State(wrappedValue: RequestDetailViewModel(request: request))
        self.namespace = namespace
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                // Only the recipient answers. The creator sees who they're waiting on,
                // and can withdraw the request instead.
                if viewModel.canRespond {
                    quickResponseRow
                } else if viewModel.isAwaitingResponse {
                    waitingRow
                }

                NegotiationView(viewModel: viewModel)

                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(MGColors.sand.ignoresSafeArea())
        .navigationTitle(viewModel.request.category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Saving is a response, so it follows the same rule as the others — it used to
            // be ungated, which let anyone flip an already-accepted request to `.saved`.
            if viewModel.canRespond {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.saveForLater() }
                    } label: {
                        Image(systemName: viewModel.request.status == .saved ? "heart.fill" : "heart")
                            .foregroundStyle(MGColors.coral)
                    }
                    .accessibilityLabel(viewModel.request.status == .saved ? "Saved for later" : "Save for later")
                }
            }
        }
        .alert("Oops", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    /// What the creator sees on their own unanswered request.
    private var waitingRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .foregroundStyle(MGColors.warm600)
                Text(viewModel.waitingMessage)
                    .mgFont(.body)
                    .foregroundStyle(MGColors.warm600)
                Spacer()
            }

            Button(role: .destructive) {
                showCancelConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Cancel request")
                        .mgFont(.body)
                    Spacer()
                }
                .foregroundStyle(MGColors.coral)
            }
            .disabled(viewModel.isSending)
            .accessibilityLabel("Cancel request")
            .accessibilityHint("Withdraws this request so your partner no longer sees it")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        // An alert rather than a confirmationDialog: on iOS 26 the dialog presents as a popover
        // whose actions are not exposed as accessibility buttons.
        .alert("Cancel this request?", isPresented: $showCancelConfirmation) {
            Button("Keep it", role: .cancel) {}
            Button("Cancel request", role: .destructive) {
                Task {
                    if await viewModel.cancelRequest() { dismiss() }
                }
            }
        } message: {
            Text("Your partner will no longer see it. This can't be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: viewModel.request.category.iconName)
                    .foregroundStyle(MGColors.indigo)
                Spacer()
                StatusBadge(status: viewModel.request.status)
            }

            Text(viewModel.request.title)
                .mgFont(.h1)

            if let details = viewModel.request.details, !details.isEmpty {
                Text(details)
                    .mgFont(.body)
                    .foregroundStyle(MGColors.warm600)
            }

            if let time = viewModel.request.proposedTime {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(time, style: .date)
                        .mgFont(.bodySmall)
                }
                .foregroundStyle(MGColors.warm600)
            }
        }
        .padding(20)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .mgShadow(MGShadow.md)
        .matchedGeometryEffect(id: "card_\(viewModel.request.id)", in: namespace, properties: .frame, anchor: .topLeading, isSource: false)
    }

    private var quickResponseRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Respond")
                .mgFont(.h3)

            HStack(spacing: 10) {
                ResponseButton(type: .accept) {
                    Task { await viewModel.respond(with: .accept) }
                }
                ResponseButton(type: .negotiate) {
                    Task { await viewModel.respond(with: .negotiate) }
                }
                ResponseButton(type: .decline) {
                    Task { await viewModel.respond(with: .decline) }
                }
                ResponseButton(type: .reschedule) {
                    viewModel.showReschedulePicker = true
                }
            }
        }
        .sheet(isPresented: $viewModel.showReschedulePicker) {
            rescheduleSheet
        }
    }

    /// Suggest a different time — the `.reschedule` response.
    private var rescheduleSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Suggest a different time for \"\(viewModel.request.title)\".")
                    .mgFont(.body)
                    .foregroundStyle(MGColors.warm600)

                DatePicker(
                    "New time",
                    selection: $viewModel.proposedNewTime,
                    in: Date()...
                )
                .datePickerStyle(.graphical)
                .tint(MGColors.indigo)

                Spacer()
            }
            .padding()
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showReschedulePicker = false }
                        .accessibilityLabel("Cancel rescheduling")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await viewModel.sendReschedule() }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isSending)
                    .accessibilityLabel("Send new time")
                }
            }
        }
        .presentationDetents([.large])
    }
}

#Preview {
    @Previewable @Namespace var namespace
    AppConfiguration.useMockRepositories = true
    return NavigationStack {
        RequestDetailView(request: .previewNegotiating, namespace: namespace)
    }
}
