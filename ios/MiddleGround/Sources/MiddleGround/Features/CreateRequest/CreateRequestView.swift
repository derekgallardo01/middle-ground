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
                    }
                }

                Section("Who?") {
                    if viewModel.isLoadingPartners {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if viewModel.relationships.isEmpty || viewModel.needsPartner {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No one has joined yet")
                                .mgFont(.body)
                            Text("Share your invite code from the Profile tab to pair up.")
                                .mgFont(.caption)
                                .foregroundStyle(MGColors.warm600)
                        }
                        .accessibilityElement(children: .combine)
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

    private func partnerID(from relationship: Relationship) -> String? {
        guard let currentUserID = viewModel.currentUser?.id else { return nil }
        return relationship.participantIDs.first { $0 != currentUserID }
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return CreateRequestView()
}
