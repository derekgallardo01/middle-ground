import SwiftUI

struct ProfileView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 100
    @ScaledMetric(relativeTo: .largeTitle) private var initialsSize: CGFloat = 36

    @Environment(AppState.self) private var appState
    @State private var viewModel = ProfileViewModel()
    @State private var showDeleteConfirmation = false
    @State private var relationshipToLeave: Relationship?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    profileHeader
                    pairingSection
                    inviteSection
                    groupsSection
                    settingsSection
                    aboutSection
                    dangerSection
                }
                .padding(.horizontal, 16)
                .mgReadableWidth()
                .padding(.vertical, 12)
            }
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            // Every failure on this screen used to be silent: the view model set
            // `errorMessage` for create-group, join-group, sign-out and delete-account, and
            // nothing rendered it. A wrong invite code just stopped the spinner. Same alert
            // pattern as OnboardingView.
            .alert("Oops", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
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
    private var pairingSection: some View {
        if viewModel.hasNoRelationship {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connect")
                    .mgFont(.h2)

                VStack(alignment: .leading, spacing: 14) {
                    Text("""
                    You're not connected with anyone yet. Start a group and share the code, \
                    or join with a code you were given.
                    """)
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.warm600)

                    Picker("Group type", selection: $viewModel.selectedRelationshipType) {
                        ForEach(RelationshipType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(MGColors.indigo)

                    Button {
                        Task { await viewModel.createGroup() }
                    } label: {
                        Text("Create a group")
                            .mgFont(.body)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MGColors.indigo)
                    .disabled(viewModel.isPairing)

                    Divider()

                    TextField("Enter invite code", text: $viewModel.joinCodeInput)
                        .mgFont(.body)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(MGColors.sand)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("Invite code")

                    Button {
                        Task { await viewModel.joinGroup() }
                    } label: {
                        Text("Join with a code")
                            .mgFont(.body)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(MGColors.indigo)
                    .disabled(!viewModel.canJoin || viewModel.isPairing)
                }
                .padding()
                .background(MGColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
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
                        .accessibilityIdentifier("inviteCode")

                    ShareLink(item: "Join me on Middle Ground with code \(code)") {
                        Label("Share invite", systemImage: "square.and.arrow.up")
                            .mgFont(.body)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MGColors.indigo)

                    // Codes used to be permanent and were never deleted after pairing, so
                    // anyone who ever saw one kept indefinite access. This is the revoke.
                    Button {
                        Task { await viewModel.regenerateInviteCode() }
                    } label: {
                        Label("Generate a new code", systemImage: "arrow.clockwise")
                            .mgFont(.bodySmall)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(MGColors.indigo)
                    .disabled(viewModel.isPairing)
                    .accessibilityHint("Replaces your invite code so the old one stops working")
                }
                .padding()
                .background(MGColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Your invite code is \(code.map(String.init).joined(separator: " "))")
            }
        }
    }

    /// Leaving is the only way out of a group short of deleting your account, and it is what
    /// backs the "block an abusive user" requirement in App Review guideline 1.2.
    @ViewBuilder
    private var groupsSection: some View {
        if !viewModel.relationships.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your groups")
                    .mgFont(.h2)

                VStack(spacing: 0) {
                    ForEach(viewModel.relationships) { relationship in
                        HStack(spacing: 12) {
                            Image(systemName: relationship.type.iconName)
                                .foregroundStyle(MGColors.indigo)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(relationship.type.displayName)
                                    .mgFont(.body)
                                Text(relationship.isPaired ? "Paired" : "Waiting for someone to join")
                                    .mgFont(.caption)
                                    .foregroundStyle(MGColors.warm600)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                relationshipToLeave = relationship
                            } label: {
                                Text("Leave")
                                    .mgFont(.bodySmall)
                                    .foregroundStyle(MGColors.coral)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isLeavingGroup)
                            .accessibilityLabel("Leave \(relationship.type.displayName) group")
                        }
                        .padding()
                        .background(MGColors.surface)
                    }
                }
                .mgCard(radius: MGRadius.lg)

                Text("Leaving removes you from the group and stops anyone in it from reaching you.")
                    .mgFont(.caption)
                    .foregroundStyle(MGColors.warm600)
            }
            .alert(
                "Leave this group?",
                isPresented: .constant(relationshipToLeave != nil),
                presenting: relationshipToLeave
            ) { relationship in
                Button("Stay", role: .cancel) { relationshipToLeave = nil }
                Button("Leave", role: .destructive) {
                    relationshipToLeave = nil
                    Task { await viewModel.leaveGroup(relationship) }
                }
            } message: { _ in
                Text("""
                You'll stop seeing each other's requests and they won't be able to send you \
                new ones. This can't be undone.
                """)
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

    /// App Store Guideline 5.1.1(v) requires in-app account deletion for any app that
    /// creates an account. Destructive and double-confirmed.
    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account")
                .mgFont(.h2)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Text("Delete Account")
                        .mgFont(.body)
                        .foregroundStyle(MGColors.coral)
                    Spacer()
                    if viewModel.isDeletingAccount {
                        ProgressView()
                    } else {
                        Image(systemName: "trash")
                            .foregroundStyle(MGColors.coral)
                    }
                }
                .padding()
                .background(MGColors.surface)
            }
            .disabled(viewModel.isDeletingAccount)
            .mgCard(radius: MGRadius.lg)
            .accessibilityLabel("Delete account")
            .accessibilityHint("Permanently removes your account and all of your data")

            Text("This permanently deletes your account, your requests, and your shared groups. It can't be undone.")
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm600)
        }
        // An alert rather than a confirmationDialog: on iOS 26 the dialog presented as a
        // popover whose actions were not exposed as accessibility buttons at all, which
        // would leave VoiceOver users unable to confirm or cancel.
        .alert("Delete your account?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task {
                    if await viewModel.deleteAccount() {
                        await appState.checkAuthState()
                    }
                }
            }
        } message: {
            Text("Everything is removed permanently and can't be recovered.")
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
