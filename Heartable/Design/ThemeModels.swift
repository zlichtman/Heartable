import SwiftUI
import UIKit

enum ThemeGroup: String, Sendable, CaseIterable {
    case light = "Light"
    case dark = "Dark"
}

/// One installed Heartable home-screen icon. `appearance` is metadata used to
/// keep the curated set balanced; the picker deliberately presents one cohesive
/// grid without exposing light/dark sections.
struct AppIconChoice: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let assetKey: String
    let appearance: ThemeGroup

    var previewAssetName: String { "themeicon-\(assetKey)" }
}

enum AppIconCatalog {
    static let coreKey = "core"

    /// A tight two-row set of dark-background Heartable marks. The recognizable
    /// heart stays constant while each accent has a distinct identity.
    static let choices: [AppIconChoice] = [
        .init(id: coreKey, label: "Heartable", assetKey: "core", appearance: .dark),
        .init(id: "carbon", label: "Claude", assetKey: "carbon", appearance: .dark),
        .init(id: "github-dark", label: "Codex", assetKey: "github-dark", appearance: .dark),
        .init(id: "neon", label: "Forest", assetKey: "neon", appearance: .dark),
        .init(id: "gruvbox-dark", label: "Ember", assetKey: "gruvbox-dark", appearance: .dark),
        .init(id: "grape", label: "Violet", assetKey: "grape", appearance: .dark),
        .init(id: "nord", label: "Frost", assetKey: "nord", appearance: .dark),
        .init(id: "noir", label: "Noir", assetKey: "noir", appearance: .dark),
    ]

    static func choice(for key: String) -> AppIconChoice? {
        choices.first { $0.id == key }
    }
}

/// One selectable theme: identity + palette. Ported from the RN `ThemeDef`.
///
/// `curated` marks a theme as part of the tight, intentional set surfaced in
/// the picker (`Themes.curated`). Non-curated palettes stay in `Themes.all`
/// (so `byKey`, persisted selections, and icon switching keep working for any
/// key) but don't render in the grid. `curatedSection` is the display section
/// the cell renders under ("Light" / "Dark" / "Signature"); it overrides the
/// legacy `section` field for picker grouping and falls back to `section` when
/// nil so existing themes don't need touching.
struct ThemeDef: Identifiable, Sendable {
    let key: String
    let label: String
    let group: ThemeGroup
    let section: String
    let subtitle: String
    let logoColor: Color
    let palette: Palette
    var curated: Bool = false
    var curatedSection: String? = nil
    var id: String { key }

    /// Section the picker groups this theme under.
    var displaySection: String { curatedSection ?? section }
}

/// The theme registry. Presets are defined in `Palettes.swift`.
enum Themes {
    static let all: [ThemeDef] = allThemeDefs
    static let defaultKey = "rosewater"

    /// The intentional, public-facing gallery. Older presets remain in `all`
    /// so persisted choices keep resolving, while every appearance surface uses
    /// this one ordered registry instead of maintaining a drifting local list.
    static let galleryKeys: [String] = [
        defaultKey,
        "archive", "blossom", "lavender", "sunset", "champagne", "rosegold",
        "matcha", "forest", "ocean", "alpine", "github-light",
        "midnight", "noir", "ember", "bordeaux", "juniper",
        "aurora", "grape", "eclipse", "catppuccin-mocha", "nord",
        "tokyo-night", "gruvbox-dark", "amber-glass", "synthwave",
    ]

    static let gallery: [ThemeDef] = galleryKeys.compactMap { key in
        all.first { $0.key == key }
    }

    /// Hue (0...1) of a theme's `logoColor`, used to sort the flat list within a
    /// group so colors flow in a rainbow rather than registry order.
    private static func hue(of c: Color) -> CGFloat {
        var h = CGFloat(0), s = CGFloat(0), b = CGFloat(0), a = CGFloat(0)
        UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return h
    }

    /// The single flat picker order: every light theme first, then every dark
    /// theme, each group sorted by `logoColor` hue. No sections, no headers.
    static let ordered: [ThemeDef] = {
        let light = all.filter { $0.group == .light }.sorted { hue(of: $0.logoColor) < hue(of: $1.logoColor) }
        let dark = all.filter { $0.group == .dark }.sorted { hue(of: $0.logoColor) < hue(of: $1.logoColor) }
        return light + dark
    }()

    static func byKey(_ key: String?) -> ThemeDef {
        if let key, let t = all.first(where: { $0.key == key }) { return t }
        return all.first(where: { $0.key == defaultKey }) ?? fallback
    }

    /// Used only if the registry is somehow empty.
    static let fallback = ThemeDef(
        key: "rosewater", label: "Rosewater", group: .dark,
        section: "Dark", subtitle: "brand pink", logoColor: Color(hex: 0xe8457c),
        palette: .fallbackDark
    )
}
