import XCTest
import SwiftUI
@testable import Heartable

@MainActor
final class FullPlayerLayoutTests: XCTestCase {
    func testPortraitLyricsAndControlsFitWithoutScrolling() async throws {
        try await render(size: CGSize(width: 390, height: 700))
    }

    func testShortPortraitLyricsAndControlsFitWithoutScrolling() async throws {
        try await render(size: CGSize(width: 320, height: 480), plain: true)
    }

    func testPortraitLargestTextKeepsLyricsVisible() async throws {
        try await render(size: CGSize(width: 375, height: 580), dark: true, largeText: true)
    }

    func testLandscapeControlsFitWithoutScrolling() async throws {
        try await render(size: CGSize(width: 724, height: 320))
    }

    func testTallLandscapeKeepsArtworkAndControlsBalanced() async throws {
        try await render(size: CGSize(width: 900, height: 500))
    }

    func testShortLandscapeWithLongTitleAndPlainLyrics() async throws {
        try await render(size: CGSize(width: 627, height: 270), plain: true)
    }

    func testLandscapeLargeTextAndDarkTheme() async throws {
        try await render(size: CGSize(width: 627, height: 270), dark: true, largeText: true)
    }

    func testLiveRadioLandscapeKeepsTransportVisible() async throws {
        try await render(size: CGSize(width: 627, height: 270), radio: true)
    }

    func testPlayerSurvivesRepeatedRotationWithoutHiddenControls() async throws {
        try await render(size: CGSize(width: 724, height: 320), rotate: true)
    }

    private func render(size: CGSize, plain: Bool = false, dark: Bool = false,
                        largeText: Bool = false, radio: Bool = false, rotate: Bool = false) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let theme = ThemeStore()
        let original = theme.currentKey
        theme.setTheme(dark ? "gruvbox-dark" : Themes.defaultKey)
        let now = PlayerStore.Now(source: radio ? .wsum : .spotify,
            name: "A very long song title from a very long album — the extended edition",
            artist: "An artist with a long name, featuring another artist", artworkURL: nil,
            isPlaying: true, positionMs: 30_000, durationMs: radio ? 0 : 180_000,
            uri: "fixture:player", providerTrackID: "fixture")
        let lyrics = plain ? LyricsModel(plain: "A line of lyrics that fits the music\nAnother line to expand and read")
            : LyricsModel(synced: [.init(timeMs: 0, text: "A line of lyrics that fits the music"),
                                  .init(timeMs: 60_000, text: "The next line waits for its moment")])
        let probe = PlayerFramesProbe()
        let host = UIHostingController(rootView:
            FullPlayerContent(now: now, lyrics: lyrics, onLyrics: {})
                .environment(theme).environment(PlayerStore()).environment(PlaybackPrefsStore())
                .environment(\.dynamicTypeSize, largeText ? .accessibility5 : .large)
                .background(theme.palette.bg)
                .ignoresSafeArea()
                .onPreferenceChange(PlayerElementFrames.self) { probe.frames = $0 }
        )
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        host.view.frame = window.bounds
        window.makeKeyAndVisible()
        defer {
            theme.setTheme(original)
            window.isHidden = true
            previous?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(700))
        try assertFits(probe.frames, in: window.bounds, radio: radio)
        XCTAssertFalse(hasVerticalOverflow(in: host.view), "The player must not require scrolling")
        if rotate {
            for _ in 0..<5 {
                for target in [CGSize(width: 390, height: 760), CGSize(width: 627, height: 270),
                               CGSize(width: 390, height: 760), size] {
                    window.frame.size = target
                    host.view.frame = window.bounds
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(150))
                    try assertFits(probe.frames, in: window.bounds, radio: radio)
                    XCTAssertFalse(hasVerticalOverflow(in: host.view))
                }
            }
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Player-\(Int(size.width))x\(Int(size.height))-dark-\(dark)-large-\(largeText)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertFits(_ frames: [String: CGRect], in bounds: CGRect, radio: Bool) throws {
        let keys = ["dismiss", "device", "artwork", "trackInfo", "scrubber", "transport",
                    "mode", "previous", "playPause", "next"] + (radio ? [] : ["lyrics"])
        for key in keys {
            let frame = try XCTUnwrap(frames[key], "Missing \(key)")
            XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(frame), "\(key) offscreen: \(frame), \(bounds)")
            XCTAssertGreaterThan(frame.height, 0)
        }
        for key in ["dismiss", "device", "mode", "previous", "playPause", "next"] {
            let frame = try XCTUnwrap(frames[key])
            XCTAssertGreaterThanOrEqual(frame.width, 44, key)
            XCTAssertGreaterThanOrEqual(frame.height, 44, key)
        }
        let title = try XCTUnwrap(frames["trackInfo"])
        let scrubber = try XCTUnwrap(frames["scrubber"])
        let transport = try XCTUnwrap(frames["transport"])
        XCTAssertLessThanOrEqual(title.maxY, scrubber.minY + 1)
        XCTAssertLessThanOrEqual(scrubber.maxY, transport.minY + 1)
        if !radio, let lyrics = frames["lyrics"], lyrics.minX >= title.minX {
            if bounds.width > bounds.height {
                XCTAssertLessThanOrEqual(title.maxY, lyrics.minY + 1)
                XCTAssertLessThanOrEqual(lyrics.maxY, scrubber.minY + 1)
            } else {
                XCTAssertLessThanOrEqual(transport.maxY, lyrics.minY + 1)
            }
        }
        if bounds.width > bounds.height, let art = frames["artwork"] {
            XCTAssertEqual(art.minY, title.minY, accuracy: 1, "Title and cover must share a top edge")
            // At accessibility sizes lyrics move beneath the artwork; the two
            // complete columns still end together.
            let leftBottom = frames["lyrics"].flatMap { $0.minX < title.minX ? $0.maxY : nil } ?? art.maxY
            XCTAssertEqual(leftBottom, transport.maxY, accuracy: 1, "Player columns must share a bottom edge")
        }
    }

    private func hasVerticalOverflow(in view: UIView) -> Bool {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 2 { return true }
        return view.subviews.contains { hasVerticalOverflow(in: $0) }
    }
}

private final class PlayerFramesProbe {
    var frames: [String: CGRect] = [:]
}
