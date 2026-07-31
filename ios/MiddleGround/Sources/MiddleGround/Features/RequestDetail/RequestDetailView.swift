import SwiftUI

struct RequestDetailView: View {
    @State private var viewModel: RequestDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCancelConfirmation = false
    var namespace: Namespace.ID

    init(request: Request, namespace: Namespace.ID) {
        _viewModel = State(wrappedValue: RequestDetailViewModel(request: request))
        self.namespace = namespace
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    // Whoever's turn it is answers; the other person waits. Both rows are
                    // absent for a moment on first render while `currentUser` loads, which is
                    // why the change is animated rather than popping into place.
                    if viewModel.canRespond {
                        quickResponseRow
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if viewModel.isAwaitingResponse {
                        waitingRow
                            .transition(.opacity)
                    }

                    NegotiationView(viewModel: viewModel)

                    Spacer(minLength: 40)
                }
                .padding()
                .mgReadableWidth()
                .animation(reduceMotion ? nil : MGMotion.standard, value: viewModel.canRespond)
                .animation(reduceMotion ? nil : MGMotion.standard, value: viewModel.request.status)
            }

            if viewModel.showCelebration {
                CelebrationView(
                    title: viewModel.celebrationTitle,
                    subtitle: "Great job working together."
                ) {
                    viewModel.showCelebration = false
                }
            }
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
            // Reporting content is required of any app carrying user-generated content
            // (App Review guideline 1.2). Leaving the group — the other required half — is
            // in Profile, and the confirmation below points there.
            if viewModel.canReport {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            viewModel.showReportSheet = true
                        } label: {
                            Label("Report this", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(MGColors.warm600)
                    }
                    .accessibilityLabel("More actions")
                }
            }
        }
        .alert("Oops", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $viewModel.showReportSheet) {
            ReportSheet(viewModel: viewModel)
        }
        .alert("Report sent", isPresented: $viewModel.didSubmitReport) {
            Button("OK") {}
        } message: {
            Text("""
            Thanks — we review every report within 24 hours. If you want this person to stop \
            reaching you entirely, leave the group from your Profile.
            """)
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

            // Ordered by intent, not arbitrarily: the two ways of saying yes-ish come first,
            // then the alternatives, then the refusal. Decline used to sit *between*
            // Negotiate and Reschedule, so the destructive option was the easiest to hit by
            // accident in a four-up row of identical buttons.
            HStack(spacing: 10) {
                ResponseButton(type: .accept, emphasis: .prominent, isBusy: viewModel.isSending) {
                    Task { await viewModel.respond(with: .accept) }
                }
                ResponseButton(type: .negotiate, isBusy: viewModel.isSending) {
                    Task { await viewModel.respond(with: .negotiate) }
                }
                ResponseButton(type: .reschedule, isBusy: viewModel.isSending) {
                    viewModel.showReschedulePicker = true
                }
                ResponseButton(type: .decline, emphasis: .quiet, isBusy: viewModel.isSending) {
                    Task { await viewModel.respond(with: .decline) }
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
