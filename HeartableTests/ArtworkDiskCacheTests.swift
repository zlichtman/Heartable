import XCTest
import UIKit
@testable import Heartable

final class ArtworkDiskCacheTests: XCTestCase {
    @MainActor func testLargeArtworkIsDownsampledBeforeCaching() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 4096, height: 2048), format: format)
            .image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4096, height: 2048))
            }
        let data = try XCTUnwrap(original.jpegData(compressionQuality: 0.8))
        let decoded = await ArtworkImageCache.decode(data)
        let bitmap = try XCTUnwrap(decoded?.cgImage)
        XCTAssertEqual(bitmap.width, 1024)
        XCTAssertEqual(bitmap.height, 512)
        XCTAssertLessThanOrEqual(bitmap.bytesPerRow * bitmap.height, 3 * 1024 * 1024)
    }

    func testOnlyNetworkArtworkURLsAreCacheable() {
        XCTAssertTrue(ArtworkDiskCache.canCache(URL(string: "https://images.example/cover.jpg")!))
        XCTAssertTrue(ArtworkDiskCache.canCache(URL(string: "http://images.example/artist.jpg")!))
        XCTAssertFalse(ArtworkDiskCache.canCache(URL(fileURLWithPath: "/private/avatar.jpg")))
        XCTAssertFalse(ArtworkDiskCache.canCache(URL(string: "data:image/png;base64,AA==")!))
    }

    func testStoreReadAndClearAreScopedToArtworkDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sibling = root.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: sibling)

        let cache = ArtworkDiskCache(directory: root)
        let url = URL(string: "https://images.example/cover.jpg")!
        let data = Data([0, 1, 2, 3])
        let generation = await cache.currentGeneration()
        await cache.store(data, for: url, generation: generation)

        let entry = await cache.entry(for: url)
        XCTAssertEqual(entry?.data, data)
        let byteCount = await cache.byteCount()
        XCTAssertEqual(byteCount, Int64(data.count))

        let artistURL = URL(string: "https://images.example/artist.jpg")!
        await cache.storeArtistImageURLs(
            ["spotify-artist": artistURL],
            generation: generation
        )
        let artistURLs = await cache.artistImageURLs()
        XCTAssertEqual(artistURLs["spotify-artist"], artistURL)

        await cache.removeAll()

        let clearedEntry = await cache.entry(for: url)
        XCTAssertNil(clearedEntry)
        let clearedArtistURLs = await cache.artistImageURLs()
        XCTAssertTrue(clearedArtistURLs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
        try? FileManager.default.removeItem(at: root)
    }

    func testClearPreventsAnOlderRequestFromRepopulatingTheCache() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = ArtworkDiskCache(directory: root)
        let url = URL(string: "https://images.example/late-cover.jpg")!
        let oldGeneration = await cache.currentGeneration()

        await cache.removeAll()
        await cache.store(Data([1, 2, 3]), for: url, generation: oldGeneration)

        let entry = await cache.entry(for: url)
        XCTAssertNil(entry)
        try? FileManager.default.removeItem(at: root)
    }
}
