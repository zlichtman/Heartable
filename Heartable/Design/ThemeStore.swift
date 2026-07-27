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
    private static let iconStorageKey = "heartable_app_icon"
    static let coreIconKey = AppIconCatalog.coreKey

    private(set) var current: ThemeDef
    private(set) var appIconKey: String
    private(set) var isChangingAppIcon = false

    /// User-authored themes (create / edit / delete, persisted). Owned here so the
    /// whole app keeps reading a single injected `ThemeStore`.
    let customThemes = CustomThemeStore()

    /// The palette every view reads.
    var palette: Palette { current.palette }

    var all: [ThemeDef] { Themes.all }

    /// The currently selected theme key.
    var currentKey: String { current.key }

    var appIconLabel: String {
        AppIconCatalog.choice(for: appIconKey)?.label ?? "Heartable"
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey)
        current = Self.resolve(saved, custom: customThemes)
        // Migrate the icon currently installed by older releases into the new,
        // independent preference. UIKit is the source of truth: a restored or
        // stale defaults value must never show an icon that is not installed.
        let installedIcon = UIApplication.shared.alternateIconName ?? Self.coreIconKey
        appIconKey = installedIcon
        UserDefaults.standard.set(installedIcon, forKey: Self.iconStorageKey)
    }

    func setTheme(_ key: String) {
        guard key != current.key else { return }
        current = Self.resolve(key, custom: customThemes)
        UserDefaults.standard.set(key, forKey: Self.storageKey)
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
    /// We set it DIRECTLY (exactly like PowderMeet + JRNL): a previous deferral +
    /// retry loop fired overlapping calls that iOS rejected with EAGAIN ("resource
    /// temporarily unavailable"). A single direct call works on dev and release.
    func setAppIcon(_ key: String) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, !isChangingAppIcon else { return }

        let name: String? = key == Self.coreIconKey ? nil : key
        guard app.alternateIconName != name else {
            appIconKey = key
            UserDefaults.standard.set(key, forKey: Self.iconStorageKey)
            return
        }
        isChangingAppIcon = true
        app.setAlternateIconName(name) { error in
            Task { @MainActor in
                self.isChangingAppIcon = false
                let installed = UIApplication.shared.alternateIconName ?? Self.coreIconKey
                self.appIconKey = installed
                UserDefaults.standard.set(installed, forKey: Self.iconStorageKey)
                if let error {
                    iconLog.error(
                        "setAlternateIconName(\(name ?? "primary", privacy: .public)) failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }
}
