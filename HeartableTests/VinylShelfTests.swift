import XCTest
import SwiftUI
@testable import Heartable

@MainActor
final class VinylShelfTests: XCTestCase {
    func testOversizedRotationProposalStopsAboveMeasuredPlayer() {
        let oversized = CGRect(x: 60, y: 80, width: 724, height: 290)
        let player = CGRect(x: 140, y: 300, width: 564, height: 44)
        let safe = PlaylistViewportBounds.availableSize(bounds: oversized, player: player)
        XCTAssertEqual(safe.height, 212)
        XCTAssertLessThanOrEqual(oversized.minY + safe.height, player.minY - 8)
        // Already-correct safe area must not lose another player-height chunk.
        let bounded = CGRect(x: 60, y: 80, width: 724, height: 200)
        XCTAssertEqual(PlaylistViewportBounds.availableSize(bounds: bounded, player: player), bounded.size)
        // Old portrait measurement is outside the new landscape viewport.
        XCTAssertEqual(PlaylistViewportBounds.availableSize(bounds: oversized,
            player: CGRect(x: 20, y: 760, width: 350, height: 44)), oversized.size)
    }

    func testRepeatedRotationWithAnOversizedContentProposal() async throws {
        try await render(themeKey: Themes.defaultKey, selection: 11, withChrome: true,
                         repeatedRotation: true)
    }

    func testRepeatedRotationKeepsFirstSleeveClearInDarkTheme() async throws {
        try await render(themeKey: "gruvbox-dark", selection: 0, withChrome: true,
                         repeatedRotation: true)
    }
    func testPlaylistChromeDoesNotChangeWhenPlaybackStartsOrStops() {
        for playing in [false, true] {
            XCTAssertTrue(PlaylistChromePolicy.reservesPlayer(playlistVisible: true, hasNowPlaying: playing))
            XCTAssertFalse(PlaylistChromePolicy.allowsMinimizing(playlistVisible: true, hasNowPlaying: playing))
        }
        XCTAssertFalse(PlaylistChromePolicy.reservesPlayer(playlistVisible: false, hasNowPlaying: false))
        XCTAssertTrue(PlaylistChromePolicy.allowsMinimizing(playlistVisible: false, hasNowPlaying: true))
    }

    func testStartingPlaybackDoesNotResizeTheLandscapeShelf() async throws {
        try await render(themeKey: Themes.defaultKey, selection: 5, withChrome: true,
                         size: CGSize(width: 667, height: 375), startPlayback: true)
    }

    func testSelectionHandlesEmptyAndChangedPlaylist() {
        XCTAssertNil(VinylShelfLayout.validSelection(3, count: 0))
        XCTAssertEqual(VinylShelfLayout.validSelection(nil, count: 10), 0)
        XCTAssertEqual(VinylShelfLayout.validSelection(-1, count: 10), 0)
        XCTAssertEqual(VinylShelfLayout.validSelection(99, count: 10), 9)
        XCTAssertEqual(VinylShelfLayout.validSelection(1, count: 3), 1)
    }

    func testSleevesKeepAccessibleTargetsAtShortHeights() {
        for height in [100.0, 200, 300, 400, 800] {
            let layout = VinylShelfLayout(size: CGSize(width: 740, height: height))
            XCTAssertGreaterThanOrEqual(layout.slotWidth, 44)
            XCTAssertLessThanOrEqual(layout.coverSize, 260)
            XCTAssertGreaterThanOrEqual(layout.coverSize, 72)
            XCTAssertLessThanOrEqual(layout.shelfHeight, height)
            XCTAssertEqual(layout.shelfWidth + layout.captionWidth + layout.panelSpacing, 740)
            XCTAssertEqual(layout.endMargin + layout.slotWidth / 2, layout.shelfWidth / 2)
        }
    }

    func testCoverFlowIsSymmetricAndDoesNotCoverTheSelectedJacket() {
        let size: CGFloat = 200
        let center = VinylShelfPose(distance: 0, coverSize: size, reduceMotion: false)
        XCTAssertEqual(center.angle, 0)
        XCTAssertEqual(center.scale, 1)
        XCTAssertEqual(center.offsetX, 0)
        let left = VinylShelfPose(distance: -1, coverSize: size, reduceMotion: false)
        let right = VinylShelfPose(distance: 1, coverSize: size, reduceMotion: false)
        XCTAssertEqual(left.angle, -right.angle)
        XCTAssertEqual(left.offsetX, -right.offsetX)
        XCTAssertEqual(left.scale, right.scale)
        let layout = VinylShelfLayout(size: CGSize(width: 740, height: 228))
        let projectedHalfWidth = size * right.scale * cos(right.angle * .pi / 180) / 2
        XCTAssertGreaterThan(layout.step + right.offsetX - projectedHalfWidth, size / 2)
        let reduced = VinylShelfPose(distance: 1, coverSize: size, reduceMotion: true)
        XCTAssertEqual(reduced.angle, 0)
        XCTAssertEqual(reduced.scale, 1)
        XCTAssertEqual(reduced.offsetY, 0)
    }

    func testShelfInWarmTheme() async throws { try await render(themeKey: Themes.defaultKey, selection: 0) }
    func testShelfInDarkTheme() async throws { try await render(themeKey: "gruvbox-dark", selection: 5) }
    func testLastSleeveWithPlayerAndTabBar() async throws {
        try await render(themeKey: Themes.defaultKey, selection: 11, withChrome: true)
    }
    func testFirstSleeveWithPlayerAndTabBar() async throws {
        try await render(themeKey: "gruvbox-dark", selection: 0, withChrome: true)
    }
    func testCompactLandscapeWithPlayerAndTabBar() async throws {
        try await render(themeKey: Themes.defaultKey, selection: 5, withChrome: true,
                         size: CGSize(width: 667, height: 375))
    }
    func testResizeKeepsLastSleeveCenteredWithoutADeferredScroll() async throws {
        try await render(themeKey: Themes.defaultKey, selection: 11, withChrome: true,
                         resizeTo: CGSize(width: 667, height: 375))
    }

    private func render(themeKey: String, selection: Int, withChrome: Bool = false,
                        size: CGSize = CGSize(width: 844, height: 390), resizeTo: CGSize? = nil,
                        startPlayback: Bool = false, repeatedRotation: Bool = false) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let theme = ThemeStore()
        let originalTheme = theme.currentKey
        theme.setTheme(themeKey)
        let generation = await ArtworkDiskCache.shared.currentGeneration()
        var tracks: [UnifiedTrack] = []
        for index in 0..<12 {
            let url = URL(string: "https://vinyl-fixture.invalid/\(UUID().uuidString).png")!
            let cover = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { context in
                UIColor(hue: CGFloat(index) / 12, saturation: 0.48, brightness: 0.64, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
                UIColor(white: 0.95, alpha: 0.75).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 45, y: 40, width: 210, height: 210))
                ("SIDE \(index + 1)" as NSString).draw(at: CGPoint(x: 20, y: 256), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 23), .foregroundColor: UIColor.white
                ])
            }
            await ArtworkDiskCache.shared.store(try XCTUnwrap(cover.pngData()), for: url, generation: generation)
            tracks.append(.init(key: "fixture\(index)", providerID: .spotify, providerTrackID: "\(index)",
                                uri: "spotify:track:\(index)", name: "A song from the collection", artists: [.init(id: "a", name: "The Artist")],
                                album: nil, albumArt: url, durationMs: 180_000))
        }
        var observedSelection: Int?
        let playback = ShelfPlaybackFixture()
        let host = UIHostingController(rootView: ShelfFixture(
            tracks: tracks, initialSelection: selection, withChrome: withChrome,
            playback: playback, oversizedProposal: repeatedRotation,
            onSelection: { observedSelection = $0 }
        ).environment(theme))
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        host.view.frame = window.bounds
        window.makeKeyAndVisible()
        defer {
            theme.setTheme(originalTheme)
            window.isHidden = true
            previous?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(1000))
        XCTAssertGreaterThan(host.view.bounds.width, host.view.bounds.height)
        XCTAssertEqual(observedSelection, selection, "Mounting must preserve the selected occurrence")
        try assertCentered(selection, count: tracks.count, in: host.view)
        if withChrome {
            let frame = try XCTUnwrap(playback.shelfFrame)
            XCTAssertLessThanOrEqual(frame.maxY, playback.playerFrame.minY,
                "Shelf must end above player: shelf=\(frame), player=\(playback.playerFrame)")
        }
        if startPlayback {
            let scroll = try XCTUnwrap(horizontalScroll(in: host.view))
            let originalFrame = scroll.convert(scroll.bounds, to: host.view)
            let originalSize = scroll.contentSize
            playback.isPlaying = true
            try await Task.sleep(for: .milliseconds(150))
            host.view.layoutIfNeeded()
            let playingScroll = try XCTUnwrap(horizontalScroll(in: host.view))
            XCTAssertEqual(playingScroll.convert(playingScroll.bounds, to: host.view), originalFrame,
                           "Starting playback must not change the shelf viewport")
            XCTAssertEqual(playingScroll.contentSize, originalSize)
            try assertCentered(selection, count: tracks.count, in: host.view)
            playback.isPlaying = false
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(playingScroll.convert(playingScroll.bounds, to: host.view), originalFrame)
        }
        if let resizeTo {
            window.frame.size = resizeTo
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(observedSelection, selection)
            try assertCentered(selection, count: tracks.count, in: host.view)
        }
        if repeatedRotation {
            for _ in 0..<5 {
                for target in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390),
                               CGSize(width: 375, height: 667), CGSize(width: 667, height: 375)] {
                    window.frame.size = target
                    host.view.frame = window.bounds
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    playback.isPlaying.toggle()
                    try await Task.sleep(for: .milliseconds(150))
                    if target.width > target.height {
                        try assertCentered(selection, count: tracks.count, in: host.view)
                        // Native scroll bounds may extend transparently into the
                        // safe area. Check the rendered ledge/cover footprint.
                        let frame = try XCTUnwrap(playback.shelfFrame)
                        XCTAssertLessThanOrEqual(frame.maxY, playback.playerFrame.minY,
                            "Repeated rotation must not overlap the player: \(frame), \(playback.playerFrame)")
                        XCTAssertEqual(observedSelection, selection)
                    }
                }
            }
        }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "Vinyl-shelf-\(themeKey)-\(selection)-chrome-\(withChrome)"
        attachment.lifetime = .keepAlways
        add(attachment)
        for track in tracks {
            if let url = track.albumArt { await ArtworkDiskCache.shared.removeEntry(for: url) }
        }
    }

    private func assertCentered(_ selection: Int, count: Int, in view: UIView) throws {
        let scroll = try XCTUnwrap(horizontalScroll(in: view))
        let insets = scroll.adjustedContentInset
        let range = scroll.contentSize.width + insets.left + insets.right - scroll.bounds.width
        let progress = (scroll.contentOffset.x + insets.left) / range
        XCTAssertEqual(progress, CGFloat(selection) / CGFloat(count - 1), accuracy: 0.005,
                       "The selected sleeve must actually be centered, not just retained in the binding. Offset: \(scroll.contentOffset), size: \(scroll.contentSize), insets: \(insets), bounds: \(scroll.bounds)")
    }

    private func horizontalScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.width > scroll.bounds.width + 10 {
            return scroll
        }
        return view.subviews.lazy.compactMap { self.horizontalScroll(in: $0) }.first
    }
}

private struct ShelfFixture: View {
    @Environment(ThemeStore.self) private var theme
    let tracks: [UnifiedTrack]
    let withChrome: Bool
    let onSelection: (Int?) -> Void
    let playback: ShelfPlaybackFixture
    let oversizedProposal: Bool
    @State private var selection: Int?

    init(tracks: [UnifiedTrack], initialSelection: Int, withChrome: Bool, playback: ShelfPlaybackFixture,
         oversizedProposal: Bool, onSelection: @escaping (Int?) -> Void) {
        self.tracks = tracks
        self.withChrome = withChrome
        self.onSelection = onSelection
        self.playback = playback
        self.oversizedProposal = oversizedProposal
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        if withChrome {
            TabView {
                Tab("", systemImage: "house") {
                    NavigationStack {
                        shelf.navigationTitle("A playlist for late nights")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .principal) {
                                    Text("A playlist for late nights").foregroundStyle(theme.palette.text)
                                }
                                ToolbarItem(placement: .topBarLeading) {
                                    Button {} label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                                }
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button {} label: { Image(systemName: "play.fill").frame(width: 44, height: 44) }
                                }
                            }
                    }
                }
                Tab("", systemImage: "heart.fill") { Color.clear }
                Tab("", systemImage: "bubble.left.and.bubble.right.fill") { Color.clear }
                Tab("", systemImage: "externaldrive.fill") { Color.clear }
                Tab("", systemImage: "person.crop.circle") { Color.clear }
            }
            .tabViewBottomAccessory {
                HStack {
                    Image(systemName: "music.note")
                    Text(playback.isPlaying ? "Now playing · A different song" : "Not Playing")
                    Spacer()
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }.padding(.horizontal, 20).foregroundStyle(theme.palette.text)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { playback.playerFrame = $0 }
            }
            .tabBarMinimizeBehavior(.never)
            .tint(theme.palette.rose)
            .environment(\.playlistPlayerFrame, playback.playerFrame)
        } else { shelf }
    }

    private var shelf: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                List(0..<50, id: \.self) { Text("Portrait track \($0)") }
                    .opacity(landscape ? 0 : 1).allowsHitTesting(!landscape).accessibilityHidden(landscape)
                if landscape {
                    PlaylistVinylViewport { size in
                        PlaylistVinylShelf(tracks: tracks, selection: $selection, viewportSize: size, onPlay: { _ in })
                    }
                }
            }
        }
        // Adversarial native proposal: withhold bottom safe-area compensation.
        // The measured player boundary must still keep the shelf clear.
        .ignoresSafeArea(.container, edges: oversizedProposal ? .bottom : [])
        .onPreferenceChange(VinylShelfLedgeFrameKey.self) { playback.shelfFrame = $0 }
        .onChange(of: selection, initial: true) { onSelection(selection) }
    }
}

@MainActor @Observable
private final class ShelfPlaybackFixture {
    var isPlaying = false
    var playerFrame: CGRect = .zero
    @ObservationIgnored var shelfFrame: CGRect?
}
