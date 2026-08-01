import SwiftUI

struct CreateRequestView: View {
    @State private var viewModel: CreateRequestViewModel
    @Environment(\.dismiss) private var dismiss
    var onCreated: ((Request) -> Void)?

    init(
        initialCategory: RequestCategory = .relationship,
        initialTitle: String = "",
        initialDetails: String = "",
        onCreated: ((Request) -> Void)? = nil
    ) {
        _viewModel = State(wrappedValue: CreateRequestViewModel(
            category: initialCategory,
            title: initialTitle,
            details: initialDetails
        ))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                // Only on a blank sheet. Once there is a title, offering to overwrite it is a
                // way to lose what someone just typed.
                if viewModel.title.isEmpty {
                    Section("Quick start") {
                        templateRow
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("What kind of request?") {
                    RequestTypePicker(selected: $viewModel.category)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section("Details") {
                    TextField("Title", text: $viewModel.title)
                        .mgFont(.body)

                    TextField("Add a note (optional)", text: $viewModel.details, axis: .vertical)
                        .mgFont(.bodySmall)
                        .lineLimit(3...6)
                }

                Section("When?") {
                    Toggle("Suggest a time", isOn: $viewModel.includeTime)
                    if viewModel.includeTime {
                        DatePicker("Proposed time", selection: $viewModel.proposedTime)
                        calendarClashRow
                    }
                }

                Section("Who?") {
                    if viewModel.isLoadingPartners {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if viewModel.relationships.isEmpty || viewModel.needsPartner {
                        // Was a text block naming the Profile tab with no way to get there —
                        // from a modal sheet, that meant dismiss, switch tab, scroll, and
                        // start over. Sharing happens inline instead.
                        InvitePrompt(code: viewModel.inviteCode, compact: true)
                    } else {
                        Picker("Recipient", selection: $viewModel.recipientID) {
                            ForEach(viewModel.relationships) { relationship in
                                Text(viewModel.label(for: relationship))
                                    .tag(partnerID(from: relationship) ?? "")
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(MGColors.slate)
                        .accessibilityLabel("Cancel creating request")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task {
                            if let request = await viewModel.createRequest() {
                                onCreated?(request)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSubmit || viewModel.isLoading)
                    .foregroundStyle(MGColors.indigo)
                    .fontWeight(.semibold)
                    .accessibilityLabel("Send request")
                }
            }
            .alert("Oops", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task {
            await viewModel.loadCurrentUserAndPartners()
        }
    }

    /// Says whether the chosen time clashes with the user's own calendar.
    ///
    /// Silent when the app cannot see the calendar. "I could not look" must never be shown as
    /// "you are free" — that is exactly how a plan gets double-booked.
    @ViewBuilder
    private var calendarClashRow: some View {
        switch viewModel.availability {
        case .busy(let title):
            Label {
                Text(title.map { "You're busy — \($0)" } ?? "You already have something then")
                    .mgFont(.bodySmall)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MGColors.sunshine)
            }
            .accessibilityLabel(
                title.map { "Warning: your calendar already has \($0) at this time" }
                    ?? "Warning: your calendar is already busy at this time"
            )

        case .free:
            Label("Your calendar is free then", systemImage: "checkmark.circle")
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)

        case .unknown where !viewModel.calendarAccessGranted:
            Button {
                Task { await viewModel.enableCalendarChecks() }
            } label: {
                Label("Check my calendar for clashes", systemImage: "calendar")
                    .mgFont(.bodySmall)
            }
            .accessibilityHint("Asks permission to read your calendar, on this device only")

        case .unknown:
            EmptyView()
        }
    }

    /// Prefills title and category, then leaves the user in the normal compose flow — the sheet
    /// stays open so they can add a note or a time before sending.
    private var templateRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MGSpacing.sm) {
                ForEach(RequestTemplate.all) { template in
                    Button {
                        viewModel.apply(template)
                        Haptics.shared.impact(.light)
                    } label: {
                        HStack(spacing: MGSpacing.xs) {
                            Text(template.emoji)
                            Text(template.title)
                                .mgFont(.bodySmall)
                                .foregroundStyle(MGColors.slate)
                        }
                        .lineLimit(1)
                        .padding(.vertical, MGSpacing.sm)
                        .padding(.horizontal, MGSpacing.md)
                        .background(MGColors.surface)
                        .clipShape(Capsule())
                        .mgShadow(MGShadow.sm)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel(template.title)
                    .accessibilityHint("Fills in the title and category for you")
                }
            }
            .padding(.horizontal, MGSpacing.lg)
            .padding(.vertical, MGSpacing.xs)
        }
    }

    private func partnerID(from relationship: Relationship) -> String? {
        guard let currentUserID = viewModel.currentUser?.id else { return nil }
        return relationship.participantIDs.first { $0 != currentUserID }
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return CreateRequestView()
}
