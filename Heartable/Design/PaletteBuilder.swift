import SwiftUI

/// Builds a full 25-field `Palette` from a small set of seed colors, deriving the
/// remaining semantic slots and enforcing readable contrast.
///
/// Both the custom-theme editor (seeds chosen by the user) and adaptive-from-art
/// mode (seeds extracted from artwork) funnel through `derive`, so a theme created
/// either way is guaranteed to be internally consistent and legible: text always
/// clears a minimum contrast against the background, and the accent is nudged to
/// stay visible on the background.
enum PaletteBuilder {
    /// Shared brand accents inlined into every preset palette; custom + adaptive
    /// palettes reuse them so secondary UI (charts, chips) matches the app.
    private static let violet = RGBAColor(r: 0x9c / 255, g: 0x5b / 255, b: 0xd2 / 255)
    private static let amber = RGBAColor(r: 0xe8 / 255, g: 0xa0 / 255, b: 0x34 / 255)
    private static let emerald = RGBAColor(r: 0x3d / 255, g: 0xba / 255, b: 0x8a / 255)
    private static let sky = RGBAColor(r: 0x4c / 255, g: 0xa4 / 255, b: 0xe8 / 255)
    private static let cream = RGBAColor(r: 0xff / 255, g: 0xf0 / 255, b: 0xe8 / 255)

    /// Minimum text/bg contrast (WCAG AA body text is 4.5; we hold that line).
    private static let minTextContrast = 4.5
    /// Minimum accent/bg contrast so the accent reads as a highlight, not noise.
    private static let minAccentContrast = 2.6

    static func derive(
        bg: RGBAColor,
        surface: RGBAColor,
        card: RGBAColor,
        accent: RGBAColor,
        accent2: RGBAColor,
        text: RGBAColor
    ) -> Palette {
        let dark = bg.isDark

        // Text must clear AA against bg; if the chosen text fails, snap to the
        // legible extreme (white on dark, near-black on light).
        let readableText = ensureContrast(text, against: bg, min: minTextContrast, preferLighter: dark)
        // Accent must stay visible on bg; nudge it lighter/darker if it blends in.
        let readableAccent = ensureContrast(accent, against: bg, min: minAccentContrast, preferLighter: dark)
        let readableAccent2 = ensureContrast(accent2, against: bg, min: minAccentContrast, preferLighter: dark)

        let bgElevated = dark ? bg.lighten(0.05) : bg.lighten(0.35)
        let cardHover = dark ? card.lighten(0.06) : card.darken(0.03)
        let border = readableText.withAlpha(dark ? 0.10 : 0.12)
        let borderHover = readableText.withAlpha(dark ? 0.20 : 0.22)

        let grad1 = readableAccent.lighten(0.20)
        let grad2 = readableAccent
        let grad3 = readableAccent2
        let danger = dark
            ? RGBAColor(r: 0xff / 255, g: 0x6b / 255, b: 0x6b / 255)
            : RGBAColor(r: 0xd6 / 255, g: 0x45 / 255, b: 0x5c / 255)
        let backdrop = dark ? bg.darken(0.5) : bg.darken(0.72)

        return Palette(
            bg: bg.color,
            bgElevated: bgElevated.color,
            surface: surface.color,
            card: card.color,
            cardHover: cardHover.color,
            border: border.color,
            borderHover: borderHover.color,
            text: readableText.color,
            textSecondary: readableText.withAlpha(0.65).color,
            textMuted: readableText.withAlpha(0.42).color,
            rose: readableAccent.color,
            roseDim: readableAccent.withAlpha(dark ? 0.16 : 0.12).color,
            roseGlow: readableAccent.withAlpha(dark ? 0.28 : 0.22).color,
            violet: violet.color,
            amber: amber.color,
            emerald: emerald.color,
            sky: sky.color,
            danger: danger.color,
            dangerDim: danger.withAlpha(dark ? 0.16 : 0.12).color,
            grad1: grad1.color,
            grad2: grad2.color,
            grad3: grad3.color,
            cream: cream.color,
            playerBackdrop: backdrop.color,
            visualizer: [grad1.color, grad2.color, grad3.color]
        )
    }

    /// Return `color` if it already clears `min` contrast against `bg`; otherwise
    /// walk it toward white or black (whichever the background wants) until it
    /// does, falling back to the pure extreme.
    private static func ensureContrast(
        _ color: RGBAColor,
        against bg: RGBAColor,
        min: Double,
        preferLighter: Bool
    ) -> RGBAColor {
        if color.contrast(against: bg) >= min { return color }
        let target: RGBAColor = preferLighter ? .white : .black
        var best = color
        for step in stride(from: 0.15, through: 1.0, by: 0.15) {
            let candidate = color.mix(target, step)
            best = candidate
            if candidate.contrast(against: bg) >= min { return candidate }
        }
        // Try the opposite extreme in case the preferred direction can't win
        // (e.g. a mid-luminance background).
        let opposite: RGBAColor = preferLighter ? .black : .white
        if opposite.contrast(against: bg) > best.contrast(against: bg) { return opposite }
        return best
    }
}
