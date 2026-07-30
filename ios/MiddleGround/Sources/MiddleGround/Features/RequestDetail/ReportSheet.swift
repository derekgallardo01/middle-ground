import SwiftUI

/// Files an abuse report against the other participant's content.
///
/// Required by App Review guideline 1.2, which asks for three things on any app carrying
/// user-generated content: a way to report it, a way to block the person, and published
/// contact details. Blocking is `RelationshipService.leave`, reachable from Profile and
/// linked from the confirmation after this sheet; contact details are in the support page.
struct ReportSheet: View {
    @Bindable var viewModel: RequestDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $viewModel.reportReason) {
                        ForEach(ReportReason.allCases) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("What's wrong?")
                }

                Section {
                    TextField("Anything else we should know?", text: $viewModel.reportNote, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Additional details")
                } header: {
                    Text("Details (optional)")
                } footer: {
                    Text("\(viewModel.reportNote.count) of \(RequestLimits.reportNote) characters")
                        .monospacedDigit()
                }

                Section {
                    Text("""
                    We review every report within 24 hours. To stop this person reaching you at \
                    all, leave the group from your Profile.
                    """)
                    .mgFont(.caption)
                    .foregroundStyle(MGColors.warm600)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await viewModel.submitReport() }
                    }
                    .disabled(viewModel.isSending)
                    .accessibilityLabel("Send report")
                }
            }
        }
    }
}
