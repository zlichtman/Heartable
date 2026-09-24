import Foundation

/// Appearance is device-wide and contains no account or listening data. Keep it
/// separate from the private content snapshot so logout clears content, not color.
struct HeartableWidgetTheme: Codable, Sendable, Equatable {
    let version: Int
    let key: String
    let background: RGBAColor
    let surface: RGBAColor
    let text: RGBAColor
    let secondaryText: RGBAColor
    let accent: RGBAColor
    let border: RGBAColor

    var isValid: Bool {
        version == 1 && !key.isEmpty &&
        [background, surface, text, secondaryText, accent, border].allSatisfy {
            [$0.r, $0.g, $0.b, $0.a].allSatisfy { $0.isFinite && (0...1).contains($0) }
        }
    }

    /// Only used before the main app has published its actual selected palette.
    static let fallback = HeartableWidgetTheme(
        version: 1, key: "rosewater",
        background: .init(r: 1, g: 244.0 / 255, b: 239.0 / 255),
        surface: .init(r: 0.98, g: 0.91, b: 0.87),
        text: .init(r: 67.0 / 255, g: 43.0 / 255, b: 43.0 / 255),
        secondaryText: .init(r: 0.50, g: 0.39, b: 0.37),
        accent: .init(r: 232.0 / 255, g: 69.0 / 255, b: 124.0 / 255),
        border: .init(r: 0.87, g: 0.77, b: 0.73)
    )
}

enum WidgetThemeStore {
    static let storageKey = "heartable.widget.theme.v1"

    static func load(defaults: UserDefaults? = nil) -> HeartableWidgetTheme {
        guard let defaults = defaults ?? UserDefaults(suiteName: WidgetSnapshotStore.appGroupIdentifier),
              let data = defaults.data(forKey: storageKey),
              let theme = try? JSONDecoder().decode(HeartableWidgetTheme.self, from: data),
              theme.isValid else { return .fallback }
        return theme
    }

    /// Returns true only for a real palette change, avoiding needless reloads
    /// when the app starts or publishes an unrelated profile/recap update.
    @discardableResult
    static func save(_ theme: HeartableWidgetTheme, defaults: UserDefaults? = nil) -> Bool {
        guard theme.isValid,
              let defaults = defaults ?? UserDefaults(suiteName: WidgetSnapshotStore.appGroupIdentifier),
              let data = try? JSONEncoder().encode(theme) else { return false }
        if let existing = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(HeartableWidgetTheme.self, from: existing),
           decoded == theme { return false }
        defaults.set(data, forKey: storageKey)
        return true
    }
}
