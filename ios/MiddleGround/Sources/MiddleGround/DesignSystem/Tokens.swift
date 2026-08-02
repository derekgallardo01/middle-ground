import SwiftUI

/// Spacing, radius, shadow and motion tokens from `brand/design-system.md`.
///
/// These existed only in the brand document; Swift inlined every value, so radii drifted
/// across 16/18/20/24/28 and the same shadow was retyped nine times. Prefer these over
/// literals so a brand change lands in one place.

enum MGSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

/// Matches `--radius-*` in brand/design-system.md. These were previously shifted a full step
/// down (md 12 vs 16, lg 16 vs 24, xl 24 vs 32), so adopting them would have made every card
/// tighter than the spec.
enum MGRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let pill: CGFloat = 9999
}

enum MGShadow {
    struct Style {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    // Radii are half the CSS blur values in brand/design-system.md, since SwiftUI's
    // `radius` is a standard deviation rather than a blur diameter.

    static var sm: Style {
        Style(color: MGColors.shadow.opacity(0.06), radius: 1, x: 0, y: 1)
    }

    /// The card shadow used across the app.
    static var md: Style {
        Style(color: MGColors.shadow.opacity(0.08), radius: 6, x: 0, y: 4)
    }

    static var lg: Style {
        Style(color: MGColors.shadow.opacity(0.12), radius: 16, x: 0, y: 12)
    }

    static func glow(_ color: Color) -> Style {
        Style(color: color.opacity(0.24), radius: 12, x: 0, y: 8)
    }
}

/// The app's motion vocabulary.
///
/// Three names, chosen for *when* they apply rather than what they are made of. Physical names
/// ("quick", "standard") do not tell you which to reach for, which is how five hand-written
/// spring literals ended up scattered through the views — two of them `standard` retyped by
/// hand, and the rest matching nothing at all.
///
/// Reach for these through `mgAnimation(_:value:)`, never `.animation()` directly: the modifier
/// is what honours Reduce Motion, and doing it by hand is how eight call sites stopped honouring
/// it at all.
enum MGMotion {
    /// Immediate feedback under a finger — a button pressing, a chip selecting. Short enough to
    /// feel like a response rather than a transition.
    static let tap = Animation.spring(response: 0.28, dampingFraction: 0.72)

    /// Content arriving, changing or moving. The default, and the right answer for almost
    /// everything: rows appearing, a status changing, a sheet's content settling.
    static let reveal = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// The one expressive moment — a plan agreed, a milestone reached. Deliberately looser and
    /// slower than everything else, so it reads as a celebration rather than a UI transition.
    /// If this is used often, it is being used wrongly.
    static let celebrate = Animation.spring(response: 0.5, dampingFraction: 0.6)
}

extension View {
    /// Applies a brand shadow token.
    func mgShadow(_ style: MGShadow.Style) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    /// Clips to a brand radius and adds the spec's 1px hairline, which is what keeps a
    /// surface-coloured card legible against the sand background.
    func mgCard(radius: CGFloat = MGRadius.lg) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(MGColors.cardBorder, lineWidth: 1)
            )
    }

    /// A complete surface card: padding, background, radius, hairline and shadow.
    ///
    /// `mgCard` only clipped and stroked, so every call site still hand-rolled the padding,
    /// the `surface` background and the shadow around it — 21 times. That is why Profile
    /// alone ended up showing four visually identical row lists at two different corner radii
    /// with two different border treatments, and why the loading skeletons had corners that
    /// visibly popped when the real content replaced them.
    ///
    /// This is the shape that makes `MGRadius` and `MGSpacing` actually load-bearing: change
    /// a token here and every card in the app moves together.
    func mgSurfaceCard(
        radius: CGFloat = MGRadius.lg,
        padding: CGFloat = MGSpacing.lg,
        shadow: MGShadow.Style? = MGShadow.md
    ) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MGColors.surface)
            .mgCard(radius: radius)
            .modifier(OptionalShadow(style: shadow))
    }

    /// Applies an animation, and honours Reduce Motion without being asked to.
    ///
    /// This used to take `reduceMotion` as a parameter, which meant every caller had to remember
    /// to read the environment and pass it in — and the result was that it was used in exactly
    /// two places in the whole app, while nine call sites hand-inlined the same ternary and eight
    /// more ignored the setting entirely. Reading the environment inside the modifier makes the
    /// accessible thing the easy thing, and the inaccessible thing impossible to write by
    /// accident.
    func mgAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MGAnimated(animation: animation, value: value))
    }

    /// A transition that collapses to nothing when Reduce Motion is on.
    ///
    /// `.transition` has no environment of its own, so an unguarded one still slides and fades
    /// for someone who asked the system not to.
    func mgTransition(_ transition: AnyTransition) -> some View {
        modifier(MGTransitioned(transition: transition))
    }
}

/// Applies a shadow only when one is supplied, so `mgSurfaceCard(shadow: nil)` is flat
/// without needing a second modifier.
private struct OptionalShadow: ViewModifier {
    let style: MGShadow.Style?

    func body(content: Content) -> some View {
        if let style {
            content.mgShadow(style)
        } else {
            content
        }
    }
}

/// Backs `mgAnimation(_:value:)`. A `ViewModifier` rather than a function on `View` because only
/// a modifier can read `@Environment` on the caller's behalf.
private struct MGAnimated<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// Backs `mgTransition(_:)`. Falls back to `.identity` — content still appears and disappears,
/// it just stops moving to do it.
private struct MGTransitioned: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let transition: AnyTransition

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .identity : transition)
    }
}
