import SwiftUI

/// Suggesting a different time for a plan that already has one.
///
/// Its own file for the same reason as `DisputeSheet`: the detail view sits at the 500-line limit
/// and a sheet is a self-contained screen.
struct RescheduleSheet: View {
    @Bindable var viewModel: RequestDetailViewModel

    var body: some View {
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

                CalendarClashRow(
                    availability: viewModel.clashChecker.availability,
                    accessGranted: viewModel.clashChecker.accessGranted
                ) {
                    Task { await viewModel.clashChecker.requestAccess(then: viewModel.proposedNewTime) }
                }

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
