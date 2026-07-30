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

enum MGRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let pill: CGFloat = 999
    /// Matches the app-icon squircle.
    static let appIcon: CGFloat = 32
}

enum MGShadow {
    struct Style {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    static var sm: Style {
        Style(color: MGColors.slate.opacity(0.05), radius: 4, x: 0, y: 1)
    }

    /// The card shadow used across the app.
    static var md: Style {
        Style(color: MGColors.slate.opacity(0.05), radius: 12, x: 0, y: 4)
    }

    static var lg: Style {
        Style(color: MGColors.slate.opacity(0.12), radius: 30, x: 0, y: 12)
    }

    static func glow(_ color: Color) -> Style {
        Style(color: color.opacity(0.3), radius: 16, x: 0, y: 8)
    }
}

enum MGMotion {
    static let quick = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let expressive = Animation.spring(response: 0.5, dampingFraction: 0.6)
}

extension View {
    /// Applies a brand shadow token.
    func mgShadow(_ style: MGShadow.Style) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    /// Rounded rectangle clip using a brand radius token.
    func mgCard(radius: CGFloat = MGRadius.xl) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Applies an animation only when Reduce Motion is off.
    ///
    /// Mirrors the pattern already used across the app so animation choices stay in one place.
    func mgAnimation<V: Equatable>(_ animation: Animation, value: V, reduceMotion: Bool) -> some View {
        self.animation(reduceMotion ? nil : animation, value: value)
    }
}
