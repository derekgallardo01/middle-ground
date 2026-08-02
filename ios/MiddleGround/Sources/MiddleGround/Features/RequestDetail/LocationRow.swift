import SwiftUI

/// Location sharing, for the hours around one plan.
///
/// Only appears while an accepted, dated plan is inside its window — an hour before until four
/// hours after. Outside that there is no row at all, rather than a disabled one: a greyed-out
/// control invites the question "why can't I?", and the honest answer is that this is not a thing
/// the app does in general, only a thing it does around a plan you both agreed to.
struct LocationRow: View {
    let mine: SharedLocation?
    let others: [SharedLocation]
    let partnerName: String
    let isBusy: Bool
    let onShare: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            Text("Where you are")
                .mgFont(.h3)

            if let mine {
                shared(mine)
            } else {
                Text("""
                     Share your location with \(partnerName) until this plan is over. \
                     One point, not a trail — and it's deleted afterwards.
                     """)
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)

                Button(action: onShare) {
                    Label("Share my location", systemImage: "location.fill")
                        .mgFont(.body)
                        .foregroundStyle(MGColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MGSpacing.sm)
                        .background(MGColors.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(isBusy)
            }

            ForEach(others) { point in
                Divider()
                theirs(point)
            }
        }
        .mgSurfaceCard()
    }

    private func shared(_ point: SharedLocation) -> some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            Label("Shared \(point.sharedAt.formatted(.relative(presentation: .named)))", systemImage: "location.fill")
                .mgFont(.bodySmall)
                .foregroundStyle(MGColors.teal)

            HStack(spacing: MGSpacing.sm) {
                Button(action: onShare) {
                    Text("Update")
                        .mgFont(.bodySmall)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MGSpacing.sm)
                        .background(MGColors.warm100)
                        .clipShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle())

                Button(action: onStop) {
                    Text("Stop sharing")
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.coral)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MGSpacing.sm)
                        .background(MGColors.warm100)
                        .clipShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .disabled(isBusy)
        }
    }

    /// Opens in Maps rather than drawing one here. A map view inside a card is a small map nobody
    /// can use; the thing people actually want from a shared pin is directions to it.
    private func theirs(_ point: SharedLocation) -> some View {
        Link(destination: mapsURL(for: point)) {
            HStack(spacing: MGSpacing.sm) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(MGColors.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(partnerName) shared their location")
                        .mgFont(.bodySmall)
                    Text(point.sharedAt.formatted(.relative(presentation: .named)))
                        .mgFont(.caption)
                        .foregroundStyle(MGColors.warm600)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .mgFont(.caption)
                    .foregroundStyle(MGColors.warm600)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Open \(partnerName)'s location in Maps")
    }

    private func mapsURL(for point: SharedLocation) -> URL {
        URL(string: "https://maps.apple.com/?ll=\(point.latitude),\(point.longitude)&q=\(partnerName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Location")")
            ?? URL(string: "https://maps.apple.com")!
    }
}

#Preview {
    VStack(spacing: MGSpacing.lg) {
        LocationRow(
            mine: nil,
            others: [],
            partnerName: "Sam",
            isBusy: false,
            onShare: {},
            onStop: {}
        )
        LocationRow(
            mine: SharedLocation(
                userID: "me",
                latitude: 40.7128,
                longitude: -74.006,
                sharedAt: Date().addingTimeInterval(-240),
                expiresAt: Date().addingTimeInterval(3600)
            ),
            others: [
                SharedLocation(
                    userID: "sam",
                    latitude: 40.7130,
                    longitude: -74.0065,
                    sharedAt: Date().addingTimeInterval(-90),
                    expiresAt: Date().addingTimeInterval(3600)
                )
            ],
            partnerName: "Sam",
            isBusy: false,
            onShare: {},
            onStop: {}
        )
    }
    .padding()
    .background(MGColors.sand)
}
