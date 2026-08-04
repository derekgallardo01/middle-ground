import SwiftUI

/// The "you need a partner first" state, with a way out of it.
///
/// Middle Ground does nothing until two people are paired, so this is the most-seen empty
/// state in the app — it appears on Home, on the create sheet, and on the spontaneous sheet.
/// All three previously said some variant of "share your invite code from the Profile tab"
/// and offered no means of doing so, which on a modal sheet meant dismissing, finding another
/// tab, and scrolling. Sharing happens here instead.
struct InvitePrompt: View {
    /// The code to share. Nil when the user has no group at all yet.
    let code: String?
    /// Shown when there is no code — the caller decides where "set up" leads.
    var onSetUp: (() -> Void)?
    /// `compact` drops the illustration and body copy for use inside a form section.
    var compact: Bool = false

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            if !compact {
                Image(systemName: "person.2")
                    .font(.system(size: 40))
                    .foregroundStyle(MGColors.indigo)
            }

            Text(compact ? "No one has joined yet" : "Invite someone to get started")
                .mgFont(compact ? .body : .h3)
                .multilineTextAlignment(.center)

            if !compact {
                Text("""
                Middle Ground works with two people. Share your code — once they join, you can \
                start sending each other requests.
                """)
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)
                    .multilineTextAlignment(.center)
            }

            if let code {
                Text(code)
                    .mgFont(compact ? .h3 : .h2)
                    .monospaced()
                    .tracking(4)
                    .foregroundStyle(MGColors.indigo)
                    // Read out character by character; "5SM5QX" is otherwise announced as an
                    // unintelligible word, and this is a string people have to transcribe.
                    .accessibilityLabel(
                        "Your invite code is \(code.map(String.init).joined(separator: " "))"
                    )

                ShareLink(
                    item: AppConfiguration.appStoreURL,
                    subject: Text("Join me on Middle Ground"),
                    message: Text("""
                    Join me on Middle Ground — my invite code is \(code)

                    Get the app, then enter the code in Profile → Connect.
                    """)
                ) {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                        .mgFont(.body, color: MGColors.onAccent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MGColors.indigo)
            } else if let onSetUp {
                Button(action: onSetUp) {
                    Text("Set up pairing")
                        .mgFont(.body, color: MGColors.onAccent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MGColors.indigo)
            }
        }
        .padding(compact ? 4 : 24)
        .frame(maxWidth: .infinity)
    }
}

#Preview("full") {
    InvitePrompt(code: "5SM5QX")
        .background(MGColors.surface)
        .padding()
        .background(MGColors.sand)
}

#Preview("compact") {
    InvitePrompt(code: "5SM5QX", compact: true)
        .padding()
        .background(MGColors.surface)
}
