import SwiftUI

enum MGColors {
    // Primary
    static let indigo = Color(hex: 0x6366F1)
    static let teal = Color(hex: 0x14B8A6)
    static let coral = Color(hex: 0xFF8FA3)
    
    // Supporting
    static let sunshine = Color(hex: 0xFFC857)
    static let lavender = Color(hex: 0xA78BFA)
    static let sky = Color(hex: 0x7DD3FC)
    
    // Neutrals
    static let sand = Color(hex: 0xF7F6F3)
    static let surface = Color.white
    static let warm100 = Color(hex: 0xF0EFEC)
    static let warm200 = Color(hex: 0xE4E3E0)
    static let warm400 = Color(hex: 0xA1A1AA)
    static let warm600 = Color(hex: 0x71717A)
    static let slate = Color(hex: 0x334155)
    
    // Gradients
    static var middleGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [indigo, Color(hex: 0x818CF8), teal]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var warmGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [coral, sunshine]),
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
}

extension RequestStatus {
    var color: Color {
        switch self {
        case .pending: return MGColors.warm600
        case .accepted, .completed: return MGColors.teal
        case .declined: return MGColors.coral
        case .negotiated, .countered: return MGColors.lavender
        case .rescheduled: return MGColors.sky
        case .saved: return MGColors.coral.opacity(0.8)
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
