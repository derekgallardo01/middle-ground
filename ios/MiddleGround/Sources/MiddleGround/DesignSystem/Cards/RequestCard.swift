import SwiftUI

struct RequestCard: View {
    let request: Request
    let onRespond: ((ResponseType) -> Void)?
    /// True while this card's response is in flight.
    var isResponding: Bool = false

    @State private var showActions = false

    /// Matched to `ResponseButton`'s glyph, so the face of the plan carries the same weight as
    /// the answers to it rather than sitting under them.
    @ScaledMetric(relativeTo: .title3) private var emojiSize: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // The plan's own face, not the category's glyph. See `Request+Emoji` for why:
                // a couple's plans are nearly all one category, so the old 14pt monochrome icon
                // was the same heart on every card in the feed.
                //
                // Hidden from VoiceOver. The row in `HomeView` already announces
                // "Request: <title>, status <status>", which is the meaning; "red heart" on top
                // of that is noise, and the emoji is a fallback often enough that reading it
                // aloud would sometimes be actively wrong about the plan.
                Text(request.displayEmoji)
                    .font(.system(size: emojiSize))
                    .accessibilityHidden(true)

                Spacer()

                StatusBadge(status: request.status)
            }

            Text(request.title)
                .mgFont(.h3, color: MGColors.slate)

            if let details = request.details, !details.isEmpty {
                Text(details)
                    .mgFont(.bodySmall, color: MGColors.warm600)
                    .lineLimit(2)
            }

            if let dates = request.dateSummary {
                HStack(spacing: 4) {
                    // A trip is a different shape of thing and gets a different icon, so a week
                    // away and a Tuesday dinner are not the same row with different words.
                    Image(systemName: request.isMultiDay ? "calendar" : "clock")
                        .font(.system(size: 12))
                    Text(dates)
                        .mgFont(.caption)
                }
                .foregroundStyle(MGColors.warm600)
            }

            // `onRespond` is only non-nil when the caller has already checked `canRespond`,
            // so it carries the turn. The old extra `isPending` test was both redundant and
            // wrong once a conversation could continue: it hid the buttons on a countered
            // request that was genuinely waiting on this user.
            if onRespond != nil {
                // Haptics are fired by the view model when the response actually lands, not
                // here on tap. Firing in both places meant accepting from the feed buzzed
                // twice — and buzzed "success" before the network had agreed.
                HStack(spacing: 8) {
                    ResponseButton(type: .accept, emphasis: .prominent, isBusy: isResponding) {
                        onRespond?(.accept)
                    }
                    ResponseButton(type: .negotiate, isBusy: isResponding) {
                        onRespond?(.negotiate)
                    }
                    ResponseButton(type: .decline, emphasis: .quiet, isBusy: isResponding) {
                        onRespond?(.decline)
                    }
                }
                // Was a bare `.transition` with no animation in scope to drive it, so the
                // response buttons appeared and vanished instantly — the modifier was doing
                // nothing at all. `mgTransition` collapses under Reduce Motion; the
                // `mgAnimation` below is what actually runs it.
                .mgTransition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Response options")
            }
        }
        // Drives the response row's transition above. `onRespond != nil` is the value that
        // decides whether those buttons exist, so it is the value the animation has to watch.
        .mgAnimation(MGMotion.reveal, value: onRespond != nil)
        .padding(16)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
        // MGShadow, not a slate tint: slate inverts to near-white in dark mode, which turned
        // the shadow on every card in the feed into a faint white halo. Colors.swift warns
        // about exactly this, and RequestCard is the most-repeated element in the app.
        .mgShadow(MGShadow.md)
    }
}

struct StatusBadge: View {
    let status: RequestStatus

    var body: some View {
        Text(status.displayName)
            // Same trap: written the other way round the badge lost its colour entirely and every
            // status read as plain slate. Legible — the fill is a 12% tint — but the colour *is*
            // the information, which is the whole reason a badge is not just a word.
            .mgFont(.caption, color: status.badgeForeground)
            .fontWeight(.bold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(status.color.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("Status: \(status.displayName)")
    }
}

#Preview {
    VStack(spacing: 16) {
        RequestCard(request: .preview) { _ in }
        RequestCard(request: .previewNegotiating, onRespond: nil)
    }
    .padding()
    .background(MGColors.sand)
}
