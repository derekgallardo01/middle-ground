import SwiftUI

struct RequestDetailView: View {
    @State private var viewModel: RequestDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCancelConfirmation = false

    /// Drives the counter composer at the bottom of the negotiation thread.
    @FocusState private var composerFocused: Bool

    /// Open straight into composing, for when the user chose "Negotiate" from the feed and the
    /// thing they actually wanted was the text field.
    private let startComposing: Bool

    init(request: Request, startComposing: Bool = false) {
        _viewModel = State(wrappedValue: RequestDetailViewModel(request: request))
        self.startComposing = startComposing
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    // Whoever's turn it is answers; the other person waits. Both are decided
                    // from `currentUserID`, which is in memory, so they are correct on the
                    // first frame rather than appearing a beat later. The animation now covers
                    // an actual change of turn, not the arrival of the viewer's own identity.
                    if viewModel.request.status == .cancelled {
                        cancelledRow
                            .transition(.opacity)
                    } else if viewModel.needsAttendanceConfirmation {
                        attendanceRow
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if viewModel.canRespond {
                        quickResponseRow
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if viewModel.isAwaitingResponse {
                        waitingRow
                            .transition(.opacity)
                    } else if let outcome = viewModel.attendanceSummary {
                        attendanceSummaryRow(outcome)
                            .transition(.opacity)
                    }

                    if let stakeState = viewModel.stakeState {
                        StakeRow(
                            state: stakeState,
                            partnerName: viewModel.partnerName ?? "your partner",
                            isBusy: viewModel.isSending,
                            onPropose: { points in
                                Task { await viewModel.proposeStake(points: points) }
                            },
                            onAccept: { Task { await viewModel.acceptStake() } }
                        )
                    }

                    NegotiationView(viewModel: viewModel, composerFocused: $composerFocused)

                    Spacer(minLength: 40)
                }
                .padding()
                .mgReadableWidth()
                .mgAnimation(MGMotion.standard, value: viewModel.canRespond, reduceMotion: reduceMotion)
                .mgAnimation(MGMotion.standard, value: viewModel.request.status, reduceMotion: reduceMotion)
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
        .task {
            // Arriving from the feed's Negotiate button: the user has already said they want to
            // suggest something, so put them in the field rather than making them find it.
            if startComposing, viewModel.canRespond {
                composerFocused = true
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

    /// Asked once the plan's time has passed: did it actually happen?
    ///
    /// The app never collected this. A request's life ended at `accepted`, so there was no record
    /// of whether anyone turned up — and nothing that depends on attendance could be built.
    private var attendanceRow: some View {
        VStack(alignment: .leading, spacing: MGSpacing.md) {
            Text("Did this happen?")
                .mgFont(.h3)
            Text("Your answer is yours alone — the other person is asked separately.")
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)

            HStack(spacing: MGSpacing.md) {
                Button {
                    Task { await viewModel.confirmAttendance(.happened) }
                } label: {
                    Label("Yes, it did", systemImage: "checkmark.circle.fill")
                        .mgFont(.body)
                        .foregroundStyle(MGColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MGSpacing.md)
                        .background(MGColors.teal)
                        .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(viewModel.isSending)

                Button {
                    Task { await viewModel.confirmAttendance(.didNotHappen) }
                } label: {
                    Label("No, it didn't", systemImage: "xmark.circle")
                        .mgFont(.body)
                        .foregroundStyle(MGColors.slate)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MGSpacing.md)
                        .background(MGColors.warm100)
                        .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(viewModel.isSending)
            }
        }
        .mgSurfaceCard()
    }

    /// Where a confirmed plan ended up, once this user has already answered.
    private func attendanceSummaryRow(_ summary: RequestDetailViewModel.AttendanceSummary) -> some View {
        let message: String
        let icon: String
        let tint: Color

        switch summary {
        case .happened:
            message = "You both confirmed this happened."
            icon = "checkmark.circle.fill"
            tint = MGColors.teal
        case .didNotHappen:
            message = "You both said this didn't happen."
            icon = "xmark.circle"
            tint = MGColors.warm600
        case .disputed:
            // Named rather than resolved. A contested plan is what an appeal would argue over,
            // so it settles nothing on its own and scores nothing either way.
            message = "You remember this differently."
            icon = "questionmark.circle"
            tint = MGColors.warm600
        case .waitingOnThem(let name):
            message = "Waiting for \(name) to confirm."
            icon = "hourglass"
            tint = MGColors.warm600
        }

        return HStack(spacing: MGSpacing.md) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(message)
                .mgFont(.body)
                .foregroundStyle(MGColors.warm600)
            Spacer()
        }
        .mgSurfaceCard()
        .accessibilityElement(children: .combine)
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
        .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        // An alert rather than a confirmationDialog: on iOS 26 the dialog presents as a popover
        // whose actions are not exposed as accessibility buttons. Each reason is its own button
        // for the same reason — a picker inside an alert is not reachable.
        .alert("Why are you cancelling?", isPresented: $showCancelConfirmation) {
            ForEach(CancellationReason.allCases) { reason in
                Button(reason.displayName) {
                    Task { await viewModel.cancelRequest(reason: reason) }
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("""
            Your partner sees that you cancelled and why. The plan stays in your history \
            rather than disappearing.
            """)
        }
    }

    /// Shown once a plan has been called off, so the record reads as a record.
    private var cancelledRow: some View {
        HStack(spacing: MGSpacing.md) {
            Image(systemName: "xmark.circle")
                .foregroundStyle(MGColors.warm600)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cancelled")
                    .mgFont(.body)
                if let reason = viewModel.request.cancellationReason {
                    Text(reason.displayName)
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.warm600)
                }
            }
            Spacer()
        }
        .mgSurfaceCard()
        .accessibilityElement(children: .combine)
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

            if let place = viewModel.request.location, !place.isEmpty {
                // Tappable, because a place name you cannot look up is barely worth storing.
                // Maps handles an unrecognised string gracefully by searching for it.
                Link(destination: viewModel.mapsURL(for: place)) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(place)
                            .mgFont(.bodySmall)
                    }
                    .foregroundStyle(MGColors.indigo)
                }
                .accessibilityLabel("Location: \(place)")
                .accessibilityHint("Opens in Maps")
            }
        }
        .padding(20)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
        .mgShadow(MGShadow.md)
        // No matchedGeometryEffect here, deliberately.
        //
        // This card used to consume the feed card's frame with `isSource: false`. The two views
        // live on opposite sides of a NavigationStack push, so the effect could never animate
        // between them — but it was not harmless either: the card took the *feed* card's
        // geometry, which pushed it hundreds of points down the screen, narrowed it until the
        // title truncated, and left the negotiation content overlapping the status badge.
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
                // Opens the composer instead of sending.
                //
                // This used to fire `.negotiate` with no text at all, which sent the other
                // person a bubble reading "🤝 Negotiate" and nothing else — and, because
                // responding hands over the turn, it simultaneously hid the one field you
                // could have explained yourself in. You could ask to negotiate but never say
                // what you wanted. Reschedule already collects its content before sending;
                // this now does the same.
                ResponseButton(type: .negotiate, isBusy: viewModel.isSending) {
                    composerFocused = true
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
    AppConfiguration.useMockRepositories = true
    return NavigationStack {
        RequestDetailView(request: .previewNegotiating)
    }
}
