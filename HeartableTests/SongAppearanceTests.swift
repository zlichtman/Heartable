import SwiftUI
import XCTest
@testable import Heartable

@MainActor
final class SongAppearanceTests: XCTestCase {
    func testStylesPreserveCompactWidthAndMinimumTapHeight() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let suite = "Heartable.SongAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); previous?.makeKey() }
        let track = UnifiedTrack(key: "spotify:test", providerID: .spotify, providerTrackID: "test",
                                 uri: "spotify:track:test", name: "A song with a longer title",
                                 artists: [.init(id: "artist", name: "The Artist")], album: nil, albumArt: nil, durationMs: 180000)
        for style in SongListStyle.allCases {
            defaults.set(style.rawValue, forKey: SongListStyle.storageKey)
            let theme = ThemeStore()
            let window = UIWindow(windowScene: scene)
            let row = UnifiedTrackRow(track: track, rank: 1, statText: "20 plays", onTap: {})
            let host = UIHostingController(rootView:
                Group {
                    if style == .covers {
                        HStack(alignment: .top, spacing: 12) { row; row }
                    } else { row }
                }
                    .padding(16).environment(theme).environment(PlaybackPrefsStore())
                    .defaultAppStorage(defaults))
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            let size = host.sizeThatFits(in: CGSize(width: 320, height: 600))
            XCTAssertLessThanOrEqual(size.width, 320)
            // UIHostingController includes the phone's top/bottom safe areas
            // in its fitting size; bound the row content, not system chrome.
            let contentHeight = size.height - host.view.safeAreaInsets.top - host.view.safeAreaInsets.bottom
            XCTAssertGreaterThanOrEqual(contentHeight, 44)
            XCTAssertLessThan(contentHeight, style == .covers ? 300 : 180)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Song-style-\(style.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    func testThemeEditorInDarkTheme() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let theme = ThemeStore()
        let oldKey = theme.currentKey
        theme.setTheme("gruvbox-dark")
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ThemeEditorView(editing: .draft())
            .environment(theme).preferredColorScheme(.dark))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey(); theme.setTheme(oldKey) }
        try await Task.sleep(for: .milliseconds(300))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Theme-editor-dark"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
