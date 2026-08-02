import SwiftUI

/// One user's full record. Opening this writes an audit entry — see `AdminViewModel.openUser`.
struct AdminUserDetailView: View {
    let user: User
    @Bindable var viewModel: AdminViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                Text("Requests (\(viewModel.selectedUserRequests.count))")
                    .mgFont(.h3)
                if viewModel.selectedUserRequests.isEmpty {
                    note("None.")
                }
                ForEach(viewModel.selectedUserRequests) { request in
                    card { AdminRequestRow(request: request) }
                }

                Text("Activity (\(viewModel.selectedUserEvents.count))")
                    .mgFont(.h3)
                if viewModel.selectedUserEvents.isEmpty {
                    note("No events recorded.")
                }
                ForEach(viewModel.selectedUserEvents) { event in
                    card {
                        HStack(spacing: 10) {
                            Image(systemName: event.type.iconName)
                                .foregroundStyle(MGColors.indigo)
                            Text(event.type.displayName).mgFont(.bodySmall)
                            Spacer()
                            Text(event.at.formatted(date: .abbreviated, time: .shortened))
                                .mgFont(.caption)
                                .foregroundStyle(MGColors.warm600)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(MGColors.sand.ignoresSafeArea())
        .navigationTitle(user.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text(user.name).mgFont(.h2)
                Text(user.id)
                    .mgFont(.caption)
                    .foregroundStyle(MGColors.warm600)
                if let stats = viewModel.statsByUser[user.id] {
                    Text("Level \(stats.level) · \(stats.relationshipXP) XP · \(stats.streakDays)-day streak")
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.warm600)
                }
                Label("This view was recorded in the audit log", systemImage: "checkmark.shield")
                    .mgFont(.caption)
                    .foregroundStyle(MGColors.warm600)
                    .padding(.top, 4)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).mgFont(.bodySmall).foregroundStyle(MGColors.warm600)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MGColors.surface)
            .mgCard(radius: MGRadius.md)
    }
}
