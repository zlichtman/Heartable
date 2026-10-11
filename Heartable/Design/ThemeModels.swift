import SwiftUI

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
        .init(id: "carbon", label: "Carbon", assetKey: "carbon", appearance: .dark),
        .init(id: "github-dark", label: "Slate", assetKey: "github-dark", appearance: .dark),
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

/// One selectable theme: identity + palette.
struct ThemeDef: Identifiable, Sendable {
    let key: String
    let label: String
    let group: ThemeGroup
    let logoColor: Color
    let palette: Palette
    var id: String { key }
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
        "tokyo-night", "gruvbox-dark", "everforest", "synthwave",
    ]

    static let gallery: [ThemeDef] = galleryKeys.compactMap { key in
        all.first { $0.key == key }
    }

    static func byKey(_ key: String?) -> ThemeDef {
        if let key, let t = all.first(where: { $0.key == key }) { return t }
        return all.first(where: { $0.key == defaultKey }) ?? fallback
    }

    /// Used only if the registry is somehow empty.
    static let fallback = ThemeDef(
        key: "rosewater", label: "Rosewater", group: .dark,
        logoColor: Color(hex: 0xe8457c),
        palette: .fallbackDark
    )
}
