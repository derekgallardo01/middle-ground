import SwiftUI

/// Booking a table for a plan that is already agreed.
///
/// The plan knows the place, the time and how many people are coming, so the one thing worth
/// doing is handing that over without making anybody type it again. The link opens OpenTable's
/// public search — no partnership, no account, nothing to sign — which is deliberately the same
/// thing people already do by hand once they have settled on somewhere.
///
/// Like `LocationRow`, it is absent rather than disabled when it does not apply. A greyed-out
/// "Book a table" on a plan nobody has agreed to yet invites a question with a boring answer.
struct BookingRow: View {
    let placeName: String
    let partySize: Int
    let url: URL
    /// Opening the link is the signal worth recording — see `BookingIntent`.
    let onOpen: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            Text("Somewhere to sit")
                .mgFont(.h3)

            // One paragraph rather than a description plus a footnote: `.caption` is semibold in
            // this design system — a badge weight — so a disclaimer set in it came out heavier
            // than the copy above it, which put the least important line at the top of the
            // hierarchy. Said plainly here instead, because the button looks like it books and
            // it does not.
            Text("""
                 Check tables at \(placeName) for \(partySize), around the time you agreed. \
                 Booking happens on OpenTable, not here.
                 """)
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.warm600)

            Button {
                onOpen()
                openURL(url)
            } label: {
                Label("Find a table", systemImage: "fork.knife")
                    .mgFont(.body, color: MGColors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MGSpacing.sm)
                    .background(MGColors.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .mgSurfaceCard()
    }
}

#Preview {
    BookingRow(
        placeName: "Lucia's",
        partySize: 3,
        url: URL(string: "https://www.opentable.com/s?term=Lucia%27s&covers=3")!
    ) {}
        .padding()
}
