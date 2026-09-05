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
            let layout = VinylShelfLayout(height: height)
            XCTAssertGreaterThanOrEqual(layout.slotWidth, 44)
            XCTAssertLessThanOrEqual(layout.coverSize, 260)
            XCTAssertGreaterThanOrEqual(layout.coverSize, 72)
        }
    }

    func testShelfInWarmTheme() async throws { try await render(themeKey: Themes.defaultKey) }
    func testShelfInDarkTheme() async throws { try await render(themeKey: "gruvbox-dark") }

    private func render(themeKey: String) async throws {
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
        let host = UIHostingController(rootView: ShelfFixture(tracks: tracks).environment(theme))
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 320)
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
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "Vinyl-shelf-\(themeKey)"
        attachment.lifetime = .keepAlways
        add(attachment)
        for track in tracks {
            if let url = track.albumArt { await ArtworkDiskCache.shared.removeEntry(for: url) }
        }
    }
}

private struct ShelfFixture: View {
    let tracks: [UnifiedTrack]
    @State private var selection: Int? = 5
    var body: some View {
        PlaylistVinylShelf(tracks: tracks, selection: $selection, onPlay: { _ in })
            .ignoresSafeArea()
    }
}
