import SwiftUI

struct RequestCard: View {
    let request: Request
    let onRespond: ((ResponseType) -> Void)?
    /// True while this card's response is in flight.
    var isResponding: Bool = false

    @State private var showActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: request.category.iconName)
                    .foregroundStyle(MGColors.indigo)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                StatusBadge(status: request.status)
            }

            Text(request.title)
                .mgFont(.h3)
                .foregroundStyle(MGColors.slate)

            if let details = request.details, !details.isEmpty {
                Text(details)
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)
                    .lineLimit(2)
            }

            if let time = request.proposedTime {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                    Text(time, style: .date)
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
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Response options")
            }
        }
        .padding(16)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            .mgFont(.caption)
            .fontWeight(.bold)
            .foregroundStyle(status.badgeForeground)
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
