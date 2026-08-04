import SwiftUI

/// The type scale from `brand/design-system.md`.
///
/// Sizes are the brand's, but they are applied through `@ScaledMetric` so they track the
/// reader's Dynamic Type setting. `Font.system(size:)` on its own is a *fixed* size with no
/// `relativeTo:` overload, which is why these are applied as a modifier rather than exposed
/// as plain `Font` constants — a `Font` value alone cannot scale.
///
/// Usage: `Text("Hi").mgFont(.h1)`
enum MGTextStyle: CaseIterable {
    case displayXL
    case displayL
    case h1
    case h2
    case h3
    case body
    case bodySmall
    case caption

    var size: CGFloat {
        switch self {
        case .displayXL: return 48
        case .displayL: return 36
        case .h1: return 28
        case .h2: return 22
        case .h3: return 18
        case .body: return 16
        case .bodySmall: return 14
        case .caption: return 12
        }
    }

    var weight: Font.Weight {
        switch self {
        case .displayXL, .displayL, .h1: return .bold
        case .h2, .h3, .caption: return .semibold
        case .body, .bodySmall: return .regular
        }
    }

    /// Headings use the rounded face; body copy uses the default face.
    var design: Font.Design {
        switch self {
        case .displayXL, .displayL, .h1, .h2, .h3: return .rounded
        case .body, .bodySmall, .caption: return .default
        }
    }

    /// The system text style each brand size tracks, which sets its scaling curve.
    var textStyle: Font.TextStyle {
        switch self {
        case .displayXL, .displayL: return .largeTitle
        case .h1: return .title
        case .h2: return .title2
        case .h3: return .title3
        case .body: return .body
        case .bodySmall: return .subheadline
        case .caption: return .caption
        }
    }
}

private struct MGScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(style: MGTextStyle) {
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
        weight = style.weight
        design = style.design
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: design))
            // Brand slate, not SwiftUI's `.primary` (pure black / pure white). Call sites can
            // still override with their own `.foregroundStyle` afterwards.
            .foregroundStyle(MGColors.slate)
    }
}

extension View {
    /// Applies a brand type style that scales with Dynamic Type.
    func mgFont(_ style: MGTextStyle) -> some View {
        modifier(MGScaledFont(style: style))
    }

    /// The same, in a colour that is not the brand slate.
    ///
    /// This exists because the obvious spelling is silently wrong. `MGScaledFont` sets
    /// `foregroundStyle(MGColors.slate)` on whatever it wraps, and SwiftUI resolves the
    /// *innermost* foreground style — so
    ///
    ///     Text("Send").mgFont(.body).foregroundStyle(MGColors.onAccent)
    ///
    /// leaves the text slate. On the indigo fill that is about 1.9:1: unreadable, and it was
    /// shipped that way on every filled button in the app because the wrong order reads
    /// perfectly naturally. Applying the colour first is what works, so this does it for you.
    func mgFont(_ style: MGTextStyle, color: Color) -> some View {
        foregroundStyle(color).modifier(MGScaledFont(style: style))
    }
}
