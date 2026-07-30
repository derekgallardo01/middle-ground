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
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// Applies a brand type style that scales with Dynamic Type.
    func mgFont(_ style: MGTextStyle) -> some View {
        modifier(MGScaledFont(style: style))
    }
}

extension View {
    func mgDisplayXL() -> some View {
        self.mgFont(.displayXL)
            .foregroundStyle(MGColors.slate)
    }

    func mgDisplayL() -> some View {
        self.mgFont(.displayL)
            .foregroundStyle(MGColors.slate)
    }

    func mgH1() -> some View {
        self.mgFont(.h1)
            .foregroundStyle(MGColors.slate)
    }

    func mgH2() -> some View {
        self.mgFont(.h2)
            .foregroundStyle(MGColors.slate)
    }

    func mgH3() -> some View {
        self.mgFont(.h3)
            .foregroundStyle(MGColors.slate)
    }

    func mgBody() -> some View {
        self.mgFont(.body)
            .foregroundStyle(MGColors.slate)
    }

    func mgBodySmall() -> some View {
        self.mgFont(.bodySmall)
            .foregroundStyle(MGColors.warm600)
    }

    func mgCaption() -> some View {
        self.mgFont(.caption)
            .foregroundStyle(MGColors.warm600)
    }
}
