import XCTest
@testable import Heartable

final class WidgetThemeTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "WidgetThemeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @MainActor
    func testEveryPresetPublishesTheExactSemanticPalette() {
        for theme in Themes.all {
            let snapshot = HeartableWidgetTheme(theme: theme)
            XCTAssertTrue(snapshot.isValid, theme.key)
            XCTAssertEqual(snapshot.key, theme.key)
            XCTAssertEqual(snapshot.background, RGBAColor(theme.palette.bg))
            XCTAssertEqual(snapshot.surface, RGBAColor(theme.palette.surface))
            XCTAssertEqual(snapshot.text, RGBAColor(theme.palette.text))
            XCTAssertEqual(snapshot.secondaryText, RGBAColor(theme.palette.textSecondary))
            XCTAssertEqual(snapshot.accent, RGBAColor(theme.palette.rose))
            XCTAssertEqual(snapshot.border, RGBAColor(theme.palette.border))
            withDefaults { defaults in
                XCTAssertTrue(WidgetThemeStore.save(snapshot, defaults: defaults))
                XCTAssertEqual(WidgetThemeStore.load(defaults: defaults), snapshot)
                XCTAssertFalse(WidgetThemeStore.save(snapshot, defaults: defaults))
            }
        }
    }

    @MainActor
    func testInPlaceCustomEditRefreshesDespiteUnchangedKey() {
        withDefaults { defaults in
            var custom = CustomTheme.draft()
            let original = HeartableWidgetTheme(theme: custom.themeDef())
            XCTAssertTrue(WidgetThemeStore.save(original, defaults: defaults))
            custom.accent = RGBAColor(r: 0.2, g: 0.8, b: 0.4)
            let edited = HeartableWidgetTheme(theme: custom.themeDef())
            XCTAssertEqual(original.key, edited.key)
            XCTAssertNotEqual(original.accent, edited.accent)
            XCTAssertTrue(WidgetThemeStore.save(edited, defaults: defaults))
            XCTAssertEqual(WidgetThemeStore.load(defaults: defaults), edited)
            // Deleting the active custom theme publishes the normal fallback.
            let fallback = HeartableWidgetTheme(theme: Themes.byKey(Themes.defaultKey))
            XCTAssertTrue(WidgetThemeStore.save(fallback, defaults: defaults))
            XCTAssertEqual(WidgetThemeStore.load(defaults: defaults), fallback)
        }
    }

    func testContentResetDoesNotDiscardDeviceAppearance() {
        withDefaults { defaults in
            WidgetThemeStore.save(.fallback, defaults: defaults)
            WidgetSnapshotStore.update(friendActivity: [
                .init(id: UUID(), friendName: "Friend", trackTitle: "Track",
                      artist: nil, playedAt: Date())
            ], defaults: defaults)
            WidgetSnapshotStore.clear(defaults: defaults)
            XCTAssertNil(WidgetSnapshotStore.load(defaults: defaults))
            XCTAssertNotNil(defaults.data(forKey: WidgetThemeStore.storageKey))
            XCTAssertEqual(WidgetThemeStore.load(defaults: defaults), .fallback)
        }
    }

    func testMissingAndCorruptSnapshotsUseSafeFallbackAndAreRepairable() {
        withDefaults { defaults in
            XCTAssertEqual(WidgetThemeStore.load(defaults: defaults), .fallback)
            defaults.set(Data("broken".utf8), forKey: WidgetThemeStore.storageKey)
            XCTAssertEqual(WidgetThemeStore.load(defaults: defaults), .fallback)
            XCTAssertTrue(WidgetThemeStore.save(.fallback, defaults: defaults))
            XCTAssertFalse(WidgetThemeStore.save(.fallback, defaults: defaults))
        }
    }

    func testUnsupportedVersionAndInvalidColorAreRejected() throws {
        try withDefaults { defaults in
            let data = try JSONEncoder().encode(HeartableWidgetTheme.fallback)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["version"] = 99
            defaults.set(try JSONSerialization.data(withJSONObject: object),
                         forKey: WidgetThemeStore.storageKey)
            XCTAssertEqual(WidgetThemeStore.load(defaults: defaults), .fallback)
            object["version"] = 1
            object["accent"] = ["r": 2.0, "g": 0.0, "b": 0.0, "a": 1.0]
            let invalidData = try JSONSerialization.data(withJSONObject: object)
            let invalid = try JSONDecoder().decode(HeartableWidgetTheme.self, from: invalidData)
            XCTAssertFalse(invalid.isValid)
            XCTAssertFalse(WidgetThemeStore.save(invalid, defaults: defaults))
            defaults.set(invalidData, forKey: WidgetThemeStore.storageKey)
            XCTAssertEqual(WidgetThemeStore.load(defaults: defaults), .fallback)
        }
    }
}
