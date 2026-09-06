import XCTest
import SwiftUI
@testable import Heartable

@MainActor
final class VinylShelfTests: XCTestCase {
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

    private func render(themeKey: String, selection: Int, withChrome: Bool = false,
                        size: CGSize = CGSize(width: 844, height: 390)) async throws {
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
        let host = UIHostingController(rootView: ShelfFixture(
            tracks: tracks, initialSelection: selection, withChrome: withChrome,
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
}

private struct ShelfFixture: View {
    @Environment(ThemeStore.self) private var theme
    let tracks: [UnifiedTrack]
    let withChrome: Bool
    let onSelection: (Int?) -> Void
    @State private var selection: Int?

    init(tracks: [UnifiedTrack], initialSelection: Int, withChrome: Bool, onSelection: @escaping (Int?) -> Void) {
        self.tracks = tracks
        self.withChrome = withChrome
        self.onSelection = onSelection
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
                    Text("Now playing · A different song")
                    Spacer()
                    Image(systemName: "pause.fill")
                }.padding(.horizontal, 20).foregroundStyle(theme.palette.text)
            }
            .tint(theme.palette.rose)
        } else { shelf }
    }

    private var shelf: some View {
        PlaylistVinylShelf(tracks: tracks, selection: $selection, onPlay: { _ in })
            .onChange(of: selection, initial: true) { onSelection(selection) }
    }
}
