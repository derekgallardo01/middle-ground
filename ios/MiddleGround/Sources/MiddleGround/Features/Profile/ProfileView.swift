import SwiftUI

struct ProfileView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 100
    @ScaledMetric(relativeTo: .largeTitle) private var initialsSize: CGFloat = 36

    @Environment(AppState.self) private var appState
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    profileHeader
                    inviteSection
                    settingsSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(MGColors.indigo.opacity(0.15))
                    .frame(width: avatarSize, height: avatarSize)
                Text(initials)
                    .font(.system(size: initialsSize, weight: .bold, design: .rounded))
                    .foregroundStyle(MGColors.indigo)
            }

            VStack(spacing: 4) {
                Text(viewModel.user?.name ?? "Guest")
                    .mgFont(.h1)
                if !viewModel.levelDisplay.isEmpty {
                    Text(viewModel.levelDisplay)
                        .mgFont(.body)
                        .foregroundStyle(MGColors.warm600)
                }
            }
        }
        .padding(24)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .mgShadow(MGShadow.md)
    }

    @ViewBuilder
    private var inviteSection: some View {
        if let code = viewModel.inviteCode, !viewModel.isPaired {
            VStack(alignment: .leading, spacing: 12) {
                Text("Invite")
                    .mgFont(.h2)

                VStack(spacing: 12) {
                    Text("Share this code so someone can join you.")
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.warm600)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(code)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(MGColors.indigo)
                        .tracking(4)

                    ShareLink(item: "Join me on Middle Ground with code \(code)") {
                        Label("Share invite", systemImage: "square.and.arrow.up")
                            .mgFont(.body)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MGColors.indigo)
                }
                .padding()
                .background(MGColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Your invite code is \(code.map(String.init).joined(separator: " "))")
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .mgFont(.h2)

            VStack(spacing: 0) {
                Toggle("Push Notifications", isOn: .init(
                    get: { viewModel.notificationsEnabled },
                    set: { desired in
                        guard desired != viewModel.notificationsEnabled else { return }
                        Task { await viewModel.toggleNotifications() }
                    }
                ))
                .mgFont(.body)
                .padding()
                .background(MGColors.surface)

                Divider()
                    .padding(.leading)

                Button {
                    Task {
                        if await viewModel.signOut() {
                            await appState.checkAuthState()
                        }
                    }
                } label: {
                    HStack {
                        Text("Sign Out")
                            .mgFont(.body)
                            .foregroundStyle(MGColors.coral)
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                        }
                    }
                    .padding()
                    .background(MGColors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .mgFont(.h2)

            VStack(spacing: 0) {
                Link(destination: AppConfiguration.supportURL) {
                    SettingRow(title: "Help & Support", icon: "questionmark.circle")
                }
                Divider().padding(.leading)
                Link(destination: AppConfiguration.privacyPolicyURL) {
                    SettingRow(title: "Privacy Policy", icon: "hand.raised")
                }
                Divider().padding(.leading)
                Link(destination: AppConfiguration.termsURL) {
                    SettingRow(title: "Terms of Service", icon: "doc.text")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var initials: String {
        guard let name = viewModel.user?.name else { return "?" }
        let components = name.split(separator: " ")
        let firstLetters = components.prefix(2).compactMap { $0.first }
        return String(firstLetters).uppercased()
    }
}

struct SettingRow: View {
    let title: String
    let icon: String

    @ScaledMetric(relativeTo: .body) private var iconColumn: CGFloat = 24

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(MGColors.indigo)
                .frame(width: iconColumn)
            Text(title)
                .mgFont(.body)
                .foregroundStyle(MGColors.slate)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MGColors.warm600)
        }
        .padding()
        .background(MGColors.surface)
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return ProfileView()
        .environment(AppState())
}
