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

    /// The other member's reliability, and nil inside a couple.
    ///
    /// Partners do not see each other's: a number one person can quote back at the other stops
    /// being feedback and becomes an argument. Groups do, because there a no-show costs someone
    /// else their evening or their booking.
    var partnerReliability: ReliabilityScore?

    let onRename: () -> Void
    let onLeave: () -> Void

    /// "Paired" was true when every group held exactly two people. It is not any more, and a
    /// three-person group reading "Paired" tells its members nothing about whether anybody else
    /// can still be added.
    private var membership: String {
        let count = relationship.participantIDs.count
        if count <= 1 { return "Waiting for someone to join" }
        let people = "\(count) \(count == 1 ? "person" : "people")"
        return relationship.hasRoom ? "\(people) · room for more" : people
    }

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
                    Text(membership)
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

            if let reliability = partnerReliability, let percentage = reliability.percentage {
                // Only once there is enough to say. Below that the card says nothing rather
                // than putting a number next to a person on two data points.
                HStack(spacing: MGSpacing.sm) {
                    Image(systemName: "figure.wave")
                        .foregroundStyle(MGColors.warm600)
                    Text("Plans with you happen \(percentage)% of the time")
                        .mgFont(.caption)
                        .foregroundStyle(MGColors.warm600)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
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
            partnerReliability: nil,
            onRename: {},
            onLeave: {}
        )
        GroupRow(
            relationship: Relationship(id: "2", participantIDs: ["a"], type: .friends),
            showsInviteCode: true,
            isLeaveDisabled: false,
            partnerReliability: nil,
            onRename: {},
            onLeave: {}
        )
    }
    .mgCard(radius: MGRadius.lg)
    .padding()
    .background(MGColors.sand)
}
