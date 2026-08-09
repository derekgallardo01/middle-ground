import SwiftUI
import UIKit

/// Brand palette, ported from `brand/color-palette.css` and `brand/dark-mode.css`.
///
/// Every token is adaptive: it resolves per trait collection, so the app follows the
/// system appearance. Previously these were fixed light values, which meant system chrome
/// went dark while every card stayed white.
enum MGColors {
    // Primary — accents lift slightly in dark mode for contrast against dark surfaces.
    static let indigo = Color(light: 0x6366F1, dark: 0x818CF8)
    /// Darkened in light mode from `#14B8A6` (teal-500) to teal-700.
    ///
    /// It is the only accent used *behind* text — the "Yes, it did" button on a settled plan —
    /// and white on teal-500 is **2.49:1**, which fails WCAG AA for body text (4.5) and for large
    /// text (3.0) alike. That is the same failure as the black-on-purple button, arrived at from
    /// the other direction: there the colour was applied wrongly, here it was applied correctly to
    /// a colour that could not carry it.
    ///
    /// Teal also reads as text and icons — a status tint, the location pin — where teal-500 on
    /// sand was 2.30:1, below even the 3:1 floor for meaningful icons. teal-700 answers both:
    /// 5.47:1 with white, 5.06:1 as text on sand. Dark mode is untouched; `#2DD4BF` behind
    /// `onAccent` is already 7.86:1.
    static let teal = Color(light: 0x0F766E, dark: 0x2DD4BF)
    static let coral = Color(light: 0xFF8FA3, dark: 0xFDA4AF)

    /// Coral, dark enough to read as text or an icon. **Use this for anything a person has to
    /// make out**; `coral` itself is a fill.
    ///
    /// The pale coral is right behind dark ink and wrong in front of a page: `#FF8FA3` on sand is
    /// **2.00:1**, under even the 3:1 floor for a meaningful icon, and it was the foreground for
    /// eleven things — the saved heart, the report button, the streak flame, "you are sharing
    /// your location". Darkening `coral` itself was not an option: it is also the fill behind
    /// `onLightAccent`, the logo mark and the confetti, all of which need it pale.
    ///
    /// rose-700 in light mode (5.82:1 on sand, 6.3:1 on white — clears AA for body text, not just
    /// the icon floor). Dark mode is unchanged, because pale coral on a dark page is already
    /// 7.74:1; the failure was only ever in light mode.
    static let coralText = Color(light: 0xBE123C, dark: 0xFDA4AF)

    // Supporting
    static let sunshine = Color(light: 0xFFC857, dark: 0xFDE68A)

    /// Sunshine, dark enough to read. Same split as `coralText`, and a worse starting point:
    /// `#FFC857` on sand is **1.42:1**, which is very nearly invisible — and it was carrying the
    /// warning triangle on the error state and the calendar clash row, the two places in the app
    /// whose entire job is to be noticed. amber-700 in light mode, 4.65:1 on sand.
    static let sunshineText = Color(light: 0xB45309, dark: 0xFDE68A)
    static let lavender = Color(light: 0xA78BFA, dark: 0xC4B5FD)
    static let sky = Color(light: 0x7DD3FC, dark: 0x7DD3FC)

    // Neutrals
    static let sand = Color(light: 0xF7F6F3, dark: 0x1E293B)
    static let surface = Color(light: 0xFFFFFF, dark: 0x334155)
    static let warm100 = Color(light: 0xF0EFEC, dark: 0x475569)
    static let warm200 = Color(light: 0xE4E3E0, dark: 0x64748B)
    static let warm400 = Color(light: 0xA1A1AA, dark: 0x94A3B8)
    static let warm600 = Color(light: 0x71717A, dark: 0xCBD5E1)
    static let slate = Color(light: 0x334155, dark: 0xF8FAFC)

    /// Foreground for text/icons sitting ON an accent fill (indigo, coral, teal…).
    ///
    /// Plain white is only correct in light mode: the accents lift in dark mode
    /// (indigo → #818CF8, coral → #FDA4AF), where white drops to ~2.9:1 and ~1.6:1.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x1E293B)

    /// Ink for accents that stay light in **both** schemes — coral, sunshine, lavender, sky.
    ///
    /// `onAccent` exists for accents that are dark in light mode and light in dark mode, so it
    /// flips. These do not flip: coral is `#FF8FA3` in light and `#FDA4AF` in dark, both pale. Ink
    /// that flips is therefore wrong twice — `onAccent` gives white on pink (2.16:1) in light, and
    /// `slate` gives near-white on pink (1.81:1) in dark. Only a fixed dark ink reads on both, at
    /// 6.76:1 and 7.74:1.
    static let onLightAccent = Color(light: 0x1E293B, dark: 0x1E293B)

    /// Shadow colour. Deliberately NOT derived from `slate`, which inverts to near-white in
    /// dark mode and turned every card shadow into a glow.
    static let shadow = Color(light: 0x334155, dark: 0x000000)

    /// Hairline border that keeps cards legible against `sand`.
    static let cardBorder = Color(light: 0xF0EFEC, dark: 0x475569)

    // Gradients
    static var middleGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [indigo, Color(hex: 0x818CF8), teal]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Resolves per appearance, so a single token works in light and dark.
    init(light: UInt, dark: UInt, alpha: Double = 1.0) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light, alpha: alpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

extension RequestStatus {
    /// Readable text colour for a badge filled with `color.opacity(0.12)`.
    ///
    /// Same-hue-on-same-hue was ~2.3:1. brand/preview.html pairs each pastel fill with a
    /// darkened text tone; these are those tones, lightened for dark mode.
    var badgeForeground: Color {
        switch self {
        case .pending: return MGColors.warm600
        case .accepted, .completed: return Color(light: 0x0F766E, dark: 0x5EEAD4)
        case .declined: return Color(light: 0x9F1239, dark: 0xFDA4AF)
        case .negotiated, .countered: return Color(light: 0x6D28D9, dark: 0xC4B5FD)
        case .rescheduled: return Color(light: 0x0369A1, dark: 0x7DD3FC)
        case .saved: return Color(light: 0x9F1239, dark: 0xFDA4AF)
        // Cancelled is history, not a failure — neutral rather than alarming.
        case .cancelled: return MGColors.warm600
        }
    }

    var color: Color {
        switch self {
        case .pending: return MGColors.warm600
        case .accepted, .completed: return MGColors.teal
        case .declined: return MGColors.coral
        case .negotiated, .countered: return MGColors.lavender
        case .rescheduled: return MGColors.sky
        case .saved: return MGColors.coral.opacity(0.8)
        case .cancelled: return MGColors.warm400
        }
    }
}

extension ResponseType {
    var color: Color {
        switch self {
        case .accept: return MGColors.teal
        case .decline: return MGColors.coral
        case .negotiate: return MGColors.lavender
        case .reschedule: return MGColors.sky
        case .counter: return MGColors.sunshine
        case .save: return MGColors.coral.opacity(0.8)
        }
    }
}
