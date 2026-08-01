import SwiftUI

/// Opens one plan to someone outside your groups.
///
/// A code for this plan alone — not an invitation into your life. There is nothing to browse and
/// nobody to match with: the only way in is a code handed to a specific person, the same shape a
/// group invite already has, so it adds no discoverability to the app.
///
/// The code admits one person and then stops working, and the creator can withdraw it before
/// anyone uses it. A code that travels by design needs both, or forwarding it is an open door.
struct PlanInviteRow: View {
    let code: String?
    let planTitle: String
    let isBusy: Bool
    let onCreate: () -> Void
    let onRevoke: () -> Void

    var body: some View {

        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            if let code {
                Text("The next person to use this code joins the plan. It then stops working.")
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)

                HStack(spacing: MGSpacing.md) {
                    Text(code)
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .foregroundStyle(MGColors.indigo)
                        .tracking(3)

                    ShareLink(
                        item: AppConfiguration.appStoreURL,
                        subject: Text(planTitle),
                        message: Text("""
                        Join me for "\(planTitle)" on Middle Ground — the code is \(code)

                        Get the app, then enter the code in Profile → Connect.
                        """)
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .mgFont(.bodySmall)
                    }
                    Spacer()

                    Button(role: .destructive) {
                        onRevoke()
                    } label: {
                        Text("Cancel")
                            .mgFont(.bodySmall)
                            .foregroundStyle(MGColors.coral)
                    }
                    .disabled(isBusy)
                    .accessibilityLabel("Cancel this plan code")
                    .accessibilityHint("Stops the code working for anyone you sent it to")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(
                    "Plan code: " + code.map(String.init).joined(separator: " ")
                )
            } else {
                Text("Inviting someone who isn't in your groups?")
                    .mgFont(.h3)
                Text("They'll get a code for this plan only — nothing else you've shared.")
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)

                Button {
                    onCreate()
                } label: {
                    Label("Create a code for this plan", systemImage: "person.badge.plus")
                        .mgFont(.bodySmall)
                }
                .disabled(isBusy)
            }
        }
        .mgSurfaceCard()
    }
}
