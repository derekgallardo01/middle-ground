import SwiftUI

/// One group in Profile's list: what it is called, whether anyone has joined, and — when several
/// groups are still waiting for someone — the invite code for *this* group specifically.
///
/// The per-group code exists because a single prominent code cannot say which group it joins.
/// Profile, Home and Compose all used to read the code from
/// `relationships.first { !$0.isPaired }`, which with more than one unpaired group picked an
/// arbitrary one — so the screen could show a code that invited someone into a group the user was
/// not thinking about.
struct GroupRow: View {
    let relationship: Relationship

    /// True only when the prominent single-group card is not already showing this same code.
    let showsInviteCode: Bool
    let isLeaveDisabled: Bool
    let onRename: () -> Void
    let onLeave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.md) {
            HStack(spacing: MGSpacing.md) {
                Image(systemName: relationship.type.iconName)
                    .foregroundStyle(MGColors.indigo)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    // The group's own name when it has one, so two groups of the same type are
                    // told apart.
                    Text(relationship.label)
                        .mgFont(.body)
                    Text(relationship.isPaired ? "Paired" : "Waiting for someone to join")
                        .mgFont(.caption)
                        .foregroundStyle(MGColors.warm600)
                }

                Spacer()

                Menu {
                    Button(action: onRename) {
                        Label(
                            relationship.name == nil ? "Name this group" : "Rename",
                            systemImage: "pencil"
                        )
                    }
                    Button(role: .destructive, action: onLeave) {
                        Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(isLeaveDisabled)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(MGColors.warm600)
                }
                .accessibilityLabel("Actions for \(relationship.label)")
            }

            if showsInviteCode {
                inviteCode
            }
        }
        .padding()
        .background(MGColors.surface)
    }

    private var inviteCode: some View {
        HStack(spacing: MGSpacing.sm) {
            Text(relationship.inviteCode)
                .font(.system(.callout, design: .monospaced).weight(.bold))
                .foregroundStyle(MGColors.indigo)
                .tracking(2)

            ShareLink(
                item: AppConfiguration.appStoreURL,
                subject: Text("Join me on Middle Ground"),
                message: Text("""
                Join me on Middle Ground — my invite code is \(relationship.inviteCode)

                Get the app, then enter the code in Profile → Connect.
                """)
            ) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share the code for \(relationship.label)")

            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(relationship.label) invite code: "
            + relationship.inviteCode.map(String.init).joined(separator: " ")
        )
    }
}

#Preview {
    VStack(spacing: 0) {
        GroupRow(
            relationship: Relationship(
                id: "1", participantIDs: ["a", "b"], type: .couple, name: "Us"
            ),
            showsInviteCode: false,
            isLeaveDisabled: false,
            onRename: {},
            onLeave: {}
        )
        GroupRow(
            relationship: Relationship(id: "2", participantIDs: ["a"], type: .friends),
            showsInviteCode: true,
            isLeaveDisabled: false,
            onRename: {},
            onLeave: {}
        )
    }
    .mgCard(radius: MGRadius.lg)
    .padding()
    .background(MGColors.sand)
}
