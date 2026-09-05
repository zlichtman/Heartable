import XCTest
import SwiftUI
@testable import Heartable

@MainActor
final class SoundSettingsLayoutTests: XCTestCase {
    func testSoundControlsInHeartableTheme() async throws {
        try await verifyLayout(crossfade: false, themeKey: Themes.defaultKey)
    }

    func testExpandedSoundControlsInDarkTheme() async throws {
        try await verifyLayout(crossfade: true, themeKey: "gruvbox-dark")
    }

    func testSoundControlsScrollWithAccessibilityText() async throws {
        try await verifyLayout(crossfade: true, themeKey: Themes.defaultKey, accessibilityText: true)
    }

    private func verifyLayout(crossfade: Bool, themeKey: String, accessibilityText: Bool = false) async throws {
        let defaults = UserDefaults.standard
        let keys = [AudioSettings.Key.volume, AudioSettings.Key.crossfade, AudioSettings.Key.crossfadeDuration]
        let originals = keys.map { defaults.object(forKey: $0) }
        let originalAudio = AudioSettings.current()
        defer {
            for (key, value) in zip(keys, originals) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
            LocalAudioEngine.shared.applySettings(originalAudio)
        }
        defaults.set(crossfade, forKey: AudioSettings.Key.crossfade)
        defaults.set(0.65, forKey: AudioSettings.Key.volume)
        defaults.set(4, forKey: AudioSettings.Key.crossfadeDuration)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        if accessibilityText {
            window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        }
        let theme = ThemeStore()
        let originalTheme = theme.currentKey
        theme.setTheme(themeKey)
        XCTAssertEqual(theme.currentKey, themeKey)
        defer { theme.setTheme(originalTheme) }
        let host = UIHostingController(rootView: NavigationStack {
            SoundsView()
        }
        .environment(theme)
        .environment(\.dynamicTypeSize, accessibilityText ? .accessibility5 : .large))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(800))
        let scroll = try XCTUnwrap(scrollViews(in: host.view).first)
        XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1,
                                 "Sound controls must not clip horizontally")
        XCTAssertEqual(AudioSettings.current().volume, 0.65)
        XCTAssertEqual(AudioSettings.current().crossfadeDuration, 4)
        attach(window, name: "Sounds-\(themeKey)-crossfade-\(crossfade)-large-\(accessibilityText)")
        if accessibilityText {
            XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
            try await Task.sleep(for: .milliseconds(100))
            attach(window, name: "Sounds-accessibility-scrolled")
        }
    }

    private func attach(_ window: UIWindow, name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }
}
