import SwiftUI

/// Full semantic color set for a theme — ported 1:1 from the RN `Palette` type.
/// Value type, Sendable. The 38 concrete palettes live in `Palettes.swift`.
struct Palette: Sendable {
    let bg: Color
    let bgElevated: Color
    let surface: Color
    let card: Color
    let cardHover: Color
    let border: Color
    let borderHover: Color
    let text: Color
    let textSecondary: Color
    let textMuted: Color
    let rose: Color          // primary accent (brand)
    let roseDim: Color
    let roseGlow: Color
    let violet: Color
    let amber: Color
    let emerald: Color
    let sky: Color
    let danger: Color
    let dangerDim: Color
    let grad1: Color
    let grad2: Color
    let grad3: Color
    let cream: Color
    let playerBackdrop: Color
    let visualizer: [Color]
}

enum Theme {
    /// Corner radii (ported from RN `radius`).
    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 18
        static let lg: CGFloat = 24
        static let xl: CGFloat = 30
        static let full: CGFloat = 999
    }
}

extension Palette {
    /// Safety fallback used before the theme registry resolves (dark rosewater).
    static let fallbackDark = Palette(
        bg: Color(hex: 0x0a0a0a), bgElevated: Color(hex: 0x141414),
        surface: Color(hex: 0x1c1c1e), card: Color(hex: 0x161618),
        cardHover: Color(hex: 0x202023), border: Color(hex: 0x2a2a2e),
        borderHover: Color(hex: 0x3a3a40),
        text: Color(hex: 0xffffff), textSecondary: Color(hex: 0xb8b8c0),
        textMuted: Color(hex: 0x77777f),
        rose: Color(hex: 0xe8457c), roseDim: Color(hex: 0xb83563),
        roseGlow: Color(hex: 0xff6fa0),
        violet: Color(hex: 0x8b5cf6), amber: Color(hex: 0xf59e0b),
        emerald: Color(hex: 0x10b981), sky: Color(hex: 0x38bdf8),
        danger: Color(hex: 0xff4d4d), dangerDim: Color(hex: 0xb83a3a),
        grad1: Color(hex: 0xff8fb3), grad2: Color(hex: 0xff6fa0),
        grad3: Color(hex: 0xe8457c),
        cream: Color(hex: 0xfff4ef), playerBackdrop: Color(hex: 0x000000),
        visualizer: [Color(hex: 0xff8fb3), Color(hex: 0xff6fa0), Color(hex: 0xe8457c)]
    )
}

extension Color {
    /// Hex literal initializer, e.g. `Color(hex: 0xe8457c)`.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}
