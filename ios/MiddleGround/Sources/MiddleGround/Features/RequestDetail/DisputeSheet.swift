import SwiftUI

/// Asking for a second look. Deliberately plain: there is nothing to choose, because the
/// disagreement is the whole subject and only one person has to describe it.
struct DisputeSheet: View {
    @Bindable var viewModel: RequestDetailViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "What do you remember?",
                        text: $viewModel.disputeNote,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .accessibilityLabel("What you remember")
                } header: {
                    Text("\"\(viewModel.request.title)\"")
                } footer: {
                    Text("""
                    Somebody here will read it. Nothing changes for either of you in the \
                    meantime — a plan you disagree about already counts for nobody.
                    """)
                }
            }
            .navigationTitle("Take a look")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showDisputeSheet = false }
                        .accessibilityLabel("Cancel asking for a review")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await viewModel.raiseDispute() } }
                        .disabled(viewModel.isSending)
                        .accessibilityLabel("Send for review")
                }
            }
        }
    }
}
