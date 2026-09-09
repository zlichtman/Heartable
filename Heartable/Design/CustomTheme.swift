import SwiftUI

/// A user-authored theme. Stores only the handful of seed colors the editor
/// exposes; the full `Palette` is derived on demand via `PaletteBuilder` so a
/// custom theme is always internally consistent and legible. `Codable` for
/// persistence, `Sendable` because it is a pure value type.
struct CustomTheme: Codable, Sendable, Identifiable, Hashable {
    /// Stable, unique theme key (also the `id`). Prefixed so it can never collide
    /// with a preset key and so `ThemeStore` can tell custom from preset at a glance.
    let id: String
    var name: String

    var bg: RGBAColor
    var surface: RGBAColor
    var card: RGBAColor
    var accent: RGBAColor
    var accent2: RGBAColor
    var text: RGBAColor

    var key: String { id }

    static let keyPrefix = "custom-"
    static func isCustomKey(_ key: String) -> Bool { key.hasPrefix(keyPrefix) }

    static func newKey() -> String { keyPrefix + UUID().uuidString }

    /// The derived full palette for this theme.
    var palette: Palette {
        PaletteBuilder.derive(
            bg: bg, surface: surface, card: card,
            accent: accent, accent2: accent2, text: text
        )
    }

    /// Bridge into the same `ThemeDef` shape presets use, so a custom theme slots
    /// into the gallery, `setTheme`, and alternate-icon logic unchanged. Grouped
    /// light/dark by background luminance.
    func themeDef() -> ThemeDef {
        ThemeDef(
            key: key,
            label: name.isEmpty ? "Custom" : name,
            group: bg.isDark ? .dark : .light,
            section: "Custom",
            subtitle: "your theme",
            logoColor: accent.color,
            palette: palette,
            curated: true,
            curatedSection: "Custom"
        )
    }

    /// A pleasant starting point for a brand-new theme (a dark rose palette),
    /// so the editor never opens on flat black.
    static func draft() -> CustomTheme {
        CustomTheme(
            id: newKey(),
            name: "",
            bg: RGBAColor(r: 0x14 / 255, g: 0x10 / 255, b: 0x16 / 255),
            surface: RGBAColor(r: 0x22 / 255, g: 0x1b / 255, b: 0x27 / 255),
            card: RGBAColor(r: 0x1f / 255, g: 0x18 / 255, b: 0x24 / 255),
            accent: RGBAColor(r: 0xff / 255, g: 0x6f / 255, b: 0xa0 / 255),
            accent2: RGBAColor(r: 0xff / 255, g: 0x9e / 255, b: 0xc1 / 255),
            text: RGBAColor(r: 0xf3 / 255, g: 0xee / 255, b: 0xf2 / 255)
        )
    }
}
