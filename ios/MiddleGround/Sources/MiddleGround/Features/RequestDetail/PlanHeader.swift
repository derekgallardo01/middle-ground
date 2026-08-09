import SwiftUI

/// The top of a plan: what it is, when it is, and where.
///
/// Split out of `RequestDetailView.swift` for the 500-line limit, the same way the trip and
/// time-zone derivations were split out of `Request.swift`. A view of its own rather than an
/// extension, because the extension could not reach the private view model — and a header that
/// takes the plan it renders is the better shape anyway: it previews on its own.
struct PlanHeader: View {

    let request: Request
    /// Supplied rather than built here, so the one place that knows how this app opens Maps
    /// stays the one place that knows.
    let mapsURL: (String) -> URL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: request.category.iconName)
                    .foregroundStyle(MGColors.indigo)
                Spacer()
                StatusBadge(status: request.status)
            }

            Text(request.title)
                .mgFont(.h1)

            if let details = request.details, !details.isEmpty {
                Text(details)
                    .mgFont(.body)
                    .foregroundStyle(MGColors.warm600)
            }

            if let dates = request.dateSummary {
                HStack(spacing: 6) {
                    Image(systemName: request.isMultiDay ? "calendar" : "clock")
                    Text(dates)
                        .mgFont(.bodySmall)
                    if let nights = request.nightCount {
                        Text("· \(nights) night\(nights == 1 ? "" : "s")")
                            .mgFont(.bodySmall)
                    }
                }
                .foregroundStyle(MGColors.warm600)
            }

            // Only ever present when the plan's clock is not the reader's, so a dinner across town
            // gains nothing to read. "8:00 PM Spain Time" is the whole point of the field: without
            // it, everybody not in Spain sees an hour that is not when the thing happens.
            if let localTime = request.localTimeSummary {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                    Text(localTime)
                        .mgFont(.bodySmall)
                }
                .foregroundStyle(MGColors.warm600)
                .accessibilityLabel("Starts at \(localTime)")
            }

            if let place = request.location, !place.isEmpty {
                // Tappable, because a place name you cannot look up is barely worth storing.
                // Maps handles an unrecognised string gracefully by searching for it.
                Link(destination: mapsURL(place)) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(place)
                            .mgFont(.bodySmall)
                    }
                    .foregroundStyle(MGColors.indigo)
                }
                .accessibilityLabel("Location: \(place)")
                .accessibilityHint("Opens in Maps")
            }
        }
        .padding(20)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
        .mgShadow(MGShadow.md)
        // No matchedGeometryEffect here, deliberately.
        //
        // This card used to consume the feed card's frame with `isSource: false`. The two views
        // live on opposite sides of a NavigationStack push, so the effect could never animate
        // between them — but it was not harmless either: the card took the *feed* card's
        // geometry, which pushed it hundreds of points down the screen, narrowed it until the
        // title truncated, and left the negotiation content overlapping the status badge.
    }
}
