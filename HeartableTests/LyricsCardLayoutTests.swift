import SwiftUI
import XCTest
@testable import Heartable

@MainActor
final class LyricsCardLayoutTests: XCTestCase {
    func testPlainLyricsAreVisibleAndScrollableInWarmTheme() async throws {
        let text = (1...20).map { "Line \($0) of a song for a friend" }.joined(separator: "\n")
        try await render(model: LyricsModel(plain: text), themeKey: Themes.defaultKey, plain: true)
    }

    func testSyncedLyricsAreVisibleInDarkTheme() async throws {
        let lines = [
            SyncedLine(timeMs: 0, text: "The record turns again"),
            SyncedLine(timeMs: 1_000, text: "A little closer to home"),
            SyncedLine(timeMs: 2_000, text: "We keep our favorite songs")
        ]
        try await render(model: LyricsModel(synced: lines), themeKey: "gruvbox-dark", plain: false)
    }

    private func render(model: LyricsModel, themeKey: String, plain: Bool) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let theme = ThemeStore()
        let oldTheme = theme.currentKey
        theme.setTheme(themeKey)
        let host = UIHostingController(rootView:
            VStack {
                LyricsCard(model: model, positionMs: 1_200, onExpand: {})
                Spacer()
            }
            .padding(20)
            .background(theme.palette.bg.ignoresSafeArea())
            .environment(theme)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            theme.setTheme(oldTheme)
            window.isHidden = true
            previous?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(300))
        if plain {
            let scroll = try XCTUnwrap(scrollViews(in: host.view).first)
            XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height + 100)
            XCTAssertLessThanOrEqual(scroll.bounds.height, 151)
        } else {
            XCTAssertTrue(scrollViews(in: host.view).isEmpty, "Synced context is inline, not a hidden scroll page")
        }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "Lyrics-card-\(themeKey)-plain-\(plain)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }
}
