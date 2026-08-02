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
    static let teal = Color(light: 0x14B8A6, dark: 0x2DD4BF)
    static let coral = Color(light: 0xFF8FA3, dark: 0xFDA4AF)

    // Supporting
    static let sunshine = Color(light: 0xFFC857, dark: 0xFDE68A)
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
