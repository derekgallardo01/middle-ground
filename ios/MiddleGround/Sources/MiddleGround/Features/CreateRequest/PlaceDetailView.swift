import Factory
import SwiftUI

/// Everything known about somewhere, before committing to it.
///
/// The chip row carries a name, a category and a distance, which is enough to recognise a place you
/// already know and not enough to choose one you do not. This is the rest of it: a picture, the
/// address, a phone number you can ring, a website, and links out to the services that hold the
/// ratings MapKit does not.
///
/// Choosing still happens here rather than being a separate step — the button is the point of the
/// screen, not an afterthought below the fold.
struct PlaceDetailView: View {
    let place: DiscoveredPlace
    let onChoose: (DiscoveredPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var picture: PlaceImage?
    @State private var isLoadingPicture = true

    private let imageProvider = Container.shared.placeImageProvider()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MGSpacing.lg) {
                    picturePanel

                    VStack(alignment: .leading, spacing: MGSpacing.xs) {
                        Text(place.name)
                            .mgFont(.h2, color: MGColors.slate)
                        if !place.subtitle.isEmpty {
                            Text(place.subtitle)
                                .mgFont(.bodySmall, color: MGColors.warm600)
                        }
                    }

                    details
                    lookupLinks
                }
                .padding(MGSpacing.lg)
            }
            .background(MGColors.sand)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Prominent and explicitly tinted. Left to the default it rendered pale grey
                    // inside the toolbar's glass capsule — beside a legible "Close" it read as
                    // disabled, which is the one thing the primary action on this screen must not.
                    Button("Choose") {
                        onChoose(place)
                        Haptics.shared.impact(.light)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MGColors.indigo)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("choosePlace")
                }
            }
        }
        .task {
            picture = await imageProvider.image(
                for: place,
                size: CGSize(width: 800, height: 500)
            )
            isLoadingPicture = false
        }
    }

    // MARK: - The picture

    @ViewBuilder
    private var picturePanel: some View {
        ZStack(alignment: .bottomLeading) {
            if let picture {
                Image(uiImage: picture.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoadingPicture {
                MGColors.warm100
                    .overlay(ProgressView())
            } else {
                // Said rather than left as a grey box, which reads as something that failed to load.
                MGColors.warm100.overlay(
                    VStack(spacing: MGSpacing.xs) {
                        Image(systemName: "photo")
                            .foregroundStyle(MGColors.warm600)
                        Text("No picture of this one")
                            .mgFont(.caption, color: MGColors.warm600)
                    }
                )
            }

            // Captioned, because a map is not a photograph and the difference matters to somebody
            // deciding whether a place looks right.
            if let caption = picture?.kind.caption {
                Text(caption)
                    .mgFont(.caption, color: .white)
                    .padding(.horizontal, MGSpacing.sm)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    // Clear of the corner. At the previous inset the capsule sat inside the
                    // radius and the clip cut it in half.
                    .padding(MGSpacing.md)
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: - What is known

    @ViewBuilder
    private var details: some View {
        VStack(spacing: 0) {
            if let address = place.address {
                detailRow(icon: "mappin.and.ellipse", label: "Address", value: address)
            }
            if let distance = place.distanceMiles {
                detailRow(
                    icon: "figure.walk",
                    label: "Distance",
                    value: String(format: "%.1f miles away", distance)
                )
            }
            if let phone = place.phone, let dial = place.telephoneURL {
                detailRow(icon: "phone", label: "Phone", value: phone) { openURL(dial) }
            }
            if let website = place.website {
                detailRow(icon: "safari", label: "Website", value: website.host() ?? "Open") {
                    openURL(website)
                }
            }
        }
        .background(MGColors.warm100)
        .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
    }

    @ViewBuilder
    private func detailRow(
        icon: String,
        label: String,
        value: String,
        action: (() -> Void)? = nil
    ) -> some View {
        let content = HStack(spacing: MGSpacing.md) {
            Image(systemName: icon)
                .foregroundStyle(MGColors.indigo)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .mgFont(.caption, color: MGColors.warm600)
                Text(value)
                    .mgFont(.body, color: MGColors.slate)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if action != nil {
                Image(systemName: "chevron.right")
                    .mgFont(.caption, color: MGColors.warm600)
            }
        }
        .padding(MGSpacing.md)

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label), \(value)")
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }

    // MARK: - The ratings we do not have

    @ViewBuilder
    private var lookupLinks: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            Text("Ratings and photos")
                .mgFont(.caption, color: MGColors.warm600)
            // The trade discovery made: Apple gives facts, not opinions. Rather than pay for
            // opinions, they are one tap away — and a link needs no key and no disclosure.
            HStack(spacing: MGSpacing.sm) {
                ForEach(PlaceLookup.allCases) { lookup in
                    if let url = lookup.url(for: place) {
                        Button(lookup.displayName) { openURL(url) }
                            .mgFont(.caption, color: MGColors.indigo)
                            .padding(.vertical, MGSpacing.sm)
                            .padding(.horizontal, MGSpacing.md)
                            .background(MGColors.warm100, in: Capsule())
                    }
                }
            }
        }
    }
}
