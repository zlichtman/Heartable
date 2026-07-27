import SwiftUI
import Observation

/// Persistence + CRUD for user-authored themes. Owned by `ThemeStore` (not
/// injected separately) so the whole app keeps reading a single `ThemeStore`.
/// Backed by a JSON blob in `UserDefaults`.
@MainActor
@Observable
final class CustomThemeStore {
    private static let storageKey = "heartable_custom_themes"

    private(set) var all: [CustomTheme] = []

    init() { load() }

    func theme(forKey key: String) -> CustomTheme? {
        all.first { $0.key == key }
    }

    /// Insert a new theme or replace the existing one with the same key.
    func upsert(_ theme: CustomTheme) {
        if let idx = all.firstIndex(where: { $0.key == theme.key }) {
            all[idx] = theme
        } else {
            all.append(theme)
        }
        persist()
    }

    func delete(_ key: String) {
        all.removeAll { $0.key == key }
        persist()
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([CustomTheme].self, from: data) {
            all = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
