import SwiftUI

/// Caps how wide a column of content is allowed to get, and centres it.
///
/// Every main screen is a single vertical list of cards. On an iPhone that fills the width and
/// looks right; on a 13" iPad the same cards stretch to ~1000pt, which leaves a request title
/// stranded at the far left of a very long white bar and a lot of dead space below the fold.
/// It reads as a phone app that was inflated rather than one that was designed.
///
/// 700pt is roughly the width at which a line of body text stops being uncomfortable to scan,
/// and it matches what Apple's own list-detail apps settle on in a regular-width window.
///
/// Deliberately a maximum, not a fixed width: on iPhone, and in a narrow iPad split view, the
/// content is narrower than the cap and nothing changes.
struct ReadableWidth: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: MGLayout.readableWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Constrains content to a comfortable reading column and centres it.
    ///
    /// The two `frame` calls are both needed and are not redundant: the first caps the content,
    /// the second makes the *container* fill the available width so the capped content ends up
    /// centred rather than pinned to the leading edge.
    func mgReadableWidth() -> some View {
        modifier(ReadableWidth())
    }
}

enum MGLayout {
    static let readableWidth: CGFloat = 700
}
