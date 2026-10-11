import SwiftUI
import UIKit
import OSLog

private let iconLog = Logger(subsystem: "com.zlichtman.heartable", category: "appicon")

/// Active theme plus an independently selected home-screen icon. Injected into
/// the environment by `HeartableApp`; views read `theme.palette.<color>`. The
/// whole app recolors through the one `palette` accessor.
@MainActor
@Observable
final class ThemeStore {
    private static let storageKey = "heartable_theme"
    static let coreIconKey = AppIconCatalog.coreKey

    private(set) var current: ThemeDef
    private(set) var appIconKey: String
    private(set) var isChangingAppIcon = false

    /// User-authored themes (create / edit / delete, persisted). Owned here so the
    /// whole app keeps reading a single injected `ThemeStore`.
    let customThemes = CustomThemeStore()

    /// The palette every view reads.
    var palette: Palette { current.palette }

    /// The currently selected theme key.
    var currentKey: String { current.key }

    init() {
        var saved = UserDefaults.standard.string(forKey: Self.storageKey)
        // The retired Amber Glass preset maps to its replacement.
        if saved == "amber-glass" {
            saved = "everforest"
            UserDefaults.standard.set(saved, forKey: Self.storageKey)
        }
        current = Self.resolve(saved, custom: customThemes)
        // UIKit is the source of truth for the installed icon, so a restored
        // device never shows an icon that is not actually installed.
        appIconKey = UIApplication.shared.alternateIconName ?? Self.coreIconKey
    }

    func setTheme(_ key: String) {
        let next = Self.resolve(key, custom: customThemes)
        guard next.key != current.key else { return }
        current = next
        UserDefaults.standard.set(next.key, forKey: Self.storageKey)
    }

    /// Resolve a key to a `ThemeDef`, checking custom themes first, then presets.
    private static func resolve(_ key: String?, custom: CustomThemeStore) -> ThemeDef {
        if let key, let c = custom.theme(forKey: key) { return c.themeDef() }
        return Themes.byKey(key)
    }

    // MARK: Custom themes

    /// Create or update a custom theme. If it's the active theme, refresh `current`
    /// so an in-place edit recolors the app immediately.
    func saveCustomTheme(_ theme: CustomTheme) {
        customThemes.upsert(theme)
        if current.key == theme.key {
            current = theme.themeDef()
        }
    }

    /// Delete a custom theme. If it was selected, fall back to the default preset.
    func deleteCustomTheme(_ key: String) {
        customThemes.delete(key)
        if current.key == key {
            setTheme(Themes.defaultKey)
        }
    }

    func customTheme(forKey key: String) -> CustomTheme? {
        customThemes.theme(forKey: key)
    }

    // MARK: Alternate app icon

    /// Select a home-screen icon without changing the in-app theme. `core`
    /// resolves to the primary dark Heartable icon; other keys map to bundled
    /// alternate app-icon asset names.
    ///
    /// Calls `setAlternateIconName` once per request: overlapping calls fail with
    /// EAGAIN ("resource temporarily unavailable"), so `isChangingAppIcon` gates
    /// re-entry until the system reports back.
    func setAppIcon(_ key: String) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, !isChangingAppIcon else { return }

        let name: String? = key == Self.coreIconKey ? nil : key
        guard app.alternateIconName != name else {
            appIconKey = key
            return
        }
        isChangingAppIcon = true
        app.setAlternateIconName(name) { error in
            Task { @MainActor in
                self.isChangingAppIcon = false
                let installed = UIApplication.shared.alternateIconName ?? Self.coreIconKey
                self.appIconKey = installed
                if let error {
                    iconLog.error(
                        "setAlternateIconName(\(name ?? "primary", privacy: .public)) failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }
}
