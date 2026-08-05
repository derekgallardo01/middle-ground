import SwiftUI

/// Getting connected, and staying able to.
///
/// Its own file because ProfileView sits at the 500-line limit, and pairing is a self-contained
/// concern: the first-run Connect card, and the "have a code?" field that has to remain reachable
/// forever afterwards.
extension ProfileView {
    @ViewBuilder
    var pairingSection: some View {
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
                            // .mgFont forces MGColors.slate, which over an indigo fill is
                            // ~1.9:1. Setting the colour afterwards does not help — SwiftUI
                            // resolves the innermost one — so this passes it in.
                            .mgFont(.body, color: MGColors.onAccent)
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
                        .clipShape(RoundedRectangle(cornerRadius: MGRadius.sm, style: .continuous))
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
                .mgCard(radius: MGRadius.md)
            }
        } else {
            joinAnotherSection
        }
    }

    /// A way in for somebody who already has a group.
    ///
    /// The Connect card above is gated on having no groups at all, which meant that anybody who
    /// created their own first could never afterwards accept somebody else's code — there was no
    /// field for it anywhere in the app. Creating a group is a thing you do once; being invited
    /// to one can happen at any time.
    var joinAnotherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Have a code?")
                .mgFont(.h2)

            VStack(alignment: .leading, spacing: 14) {
                Text("Somebody sent you an invite? Enter it here.")
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)

                TextField("Enter invite code", text: $viewModel.joinCodeInput)
                    .mgFont(.body)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(MGColors.sand)
                    .clipShape(RoundedRectangle(cornerRadius: MGRadius.sm, style: .continuous))
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
            .mgCard(radius: MGRadius.md)
        }
    }
}
