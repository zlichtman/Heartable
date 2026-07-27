import SwiftUI
import UIKit
import CryptoKit

struct ArtworkDiskEntry: Sendable {
    let data: Data
    let needsRefresh: Bool
}

/// A bounded, disposable cache for public provider artwork. Files live in the
/// system Caches directory so iOS may reclaim them under storage pressure.
actor ArtworkDiskCache {
    static let shared = ArtworkDiskCache()

    static let directoryName = "HeartableArtwork-v1"
    static let maximumBytes: Int64 = 256 * 1_024 * 1_024
    static let maximumFileCount = 2_000
    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60

    private let fileManager: FileManager
    private let directory: URL
    private var generation = 0
    private var imagesDirectory: URL {
        directory.appendingPathComponent("images", isDirectory: true)
    }
    private var artistURLsFile: URL {
        directory.appendingPathComponent("artist-urls.json", isDirectory: false)
    }

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil
    ) {
        self.fileManager = fileManager
        let caches = directory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = caches.appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    static func canCache(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    func entry(for url: URL) -> ArtworkDiskEntry? {
        guard Self.canCache(url) else { return nil }
        let file = fileURL(for: url)
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else {
            return nil
        }
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
        let modified = values?.contentModificationDate ?? .distantPast
        var resourceValues = URLResourceValues()
        resourceValues.contentAccessDate = Date()
        var touchedFile = file
        try? touchedFile.setResourceValues(resourceValues)
        return ArtworkDiskEntry(
            data: data,
            needsRefresh: Date().timeIntervalSince(modified) >= Self.refreshInterval
        )
    }

    func currentGeneration() -> Int {
        generation
    }

    func store(_ data: Data, for url: URL, generation expectedGeneration: Int) {
        guard generation == expectedGeneration,
              Self.canCache(url),
              !data.isEmpty else { return }
        do {
            try fileManager.createDirectory(
                at: imagesDirectory,
                withIntermediateDirectories: true
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var cacheDirectory = directory
            try? cacheDirectory.setResourceValues(values)
            try data.write(to: fileURL(for: url), options: .atomic)
            trimIfNeeded()
        } catch {
            // Artwork is an optimization. A full disk or a purged cache should
            // never make the surrounding music UI fail.
        }
    }

    func byteCount() -> Int64 {
        cachedFiles().reduce(0) { partial, file in
            let values = try? file.resourceValues(forKeys: [.fileSizeKey])
            return partial + Int64(values?.fileSize ?? 0)
        }
    }

    func removeAll() {
        generation += 1
        try? fileManager.removeItem(at: directory)
    }

    func removeEntry(for url: URL) {
        try? fileManager.removeItem(at: fileURL(for: url))
    }

    func artistImageURLs() -> [String: URL] {
        guard let data = try? Data(contentsOf: artistURLsFile),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return values.reduce(into: [:]) { result, pair in
            if let url = URL(string: pair.value), Self.canCache(url) {
                result[pair.key] = url
            }
        }
    }

    func storeArtistImageURLs(_ values: [String: URL], generation expectedGeneration: Int) {
        guard generation == expectedGeneration else { return }
        let encodable = values.mapValues(\.absoluteString)
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: artistURLsFile, options: .atomic)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var cacheDirectory = directory
            try? cacheDirectory.setResourceValues(resourceValues)
        } catch {
            // The artist photo URL is an optimization and can be fetched again.
        }
    }

    private func fileURL(for url: URL) -> URL {
        var normalized = url
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.fragment = nil
            normalized = components.url ?? url
        }
        let digest = SHA256.hash(data: Data(normalized.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return imagesDirectory.appendingPathComponent(digest, isDirectory: false)
    }

    private func cachedFiles() -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func trimIfNeeded() {
        let files = cachedFiles().map { file -> (URL, Int64, Date) in
            let values = try? file.resourceValues(
                forKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]
            )
            return (
                file,
                Int64(values?.fileSize ?? 0),
                values?.contentAccessDate ?? values?.contentModificationDate ?? .distantPast
            )
        }
        var total = files.reduce(Int64(0)) { $0 + $1.1 }
        var count = files.count
        guard total > Self.maximumBytes || count > Self.maximumFileCount else { return }
        for file in files.sorted(by: { $0.2 < $1.2 }) {
            try? fileManager.removeItem(at: file.0)
            total -= file.1
            count -= 1
            if total <= Self.maximumBytes && count <= Self.maximumFileCount { break }
        }
    }
}

/// Keeps decoded artwork in memory in addition to URLCache's encoded response.
/// Player polling rebuilds view values every few seconds; serving the decoded
/// image synchronously prevents those refreshes from flashing a placeholder.
@MainActor
final class ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private let images = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<Data?, Never>] = [:]
    private let session: URLSession
    private var generation = 0

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        images.countLimit = 300
        images.totalCostLimit = 80 * 1_024 * 1_024
    }

    func image(for url: URL) -> UIImage? {
        images.object(forKey: url as NSURL)
    }

    func load(
        _ url: URL,
        expectedGeneration: Int? = nil
    ) async -> UIImage? {
        guard expectedGeneration == nil || expectedGeneration == generation else {
            return nil
        }
        if let cached = image(for: url) { return cached }
        guard ArtworkDiskCache.canCache(url) else { return nil }
        let requestedGeneration = generation

        if let entry = await ArtworkDiskCache.shared.entry(for: url) {
            if let image = await Self.decode(entry.data),
               requestedGeneration == generation,
               expectedGeneration == nil || expectedGeneration == generation {
                remember(image, for: url, encodedByteCount: entry.data.count)
                if entry.needsRefresh {
                    Task { [weak self] in
                        await self?.refresh(
                            url,
                            expectedGeneration: requestedGeneration
                        )
                    }
                }
                return image
            }
            guard requestedGeneration == generation else { return nil }
            await ArtworkDiskCache.shared.removeEntry(for: url)
        }

        let diskGeneration = await ArtworkDiskCache.shared.currentGeneration()
        guard let data = await fetch(url),
              let image = await Self.decode(data),
              requestedGeneration == generation,
              expectedGeneration == nil || expectedGeneration == generation else {
            return nil
        }
        await ArtworkDiskCache.shared.store(data, for: url, generation: diskGeneration)
        guard requestedGeneration == generation,
              expectedGeneration == nil || expectedGeneration == generation else {
            return nil
        }
        remember(image, for: url, encodedByteCount: data.count)
        return image
    }

    func byteCount() async -> Int64 {
        await ArtworkDiskCache.shared.byteCount()
    }

    func clear() async {
        generation += 1
        images.removeAllObjects()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        await ArtworkDiskCache.shared.removeAll()
    }

    /// Warm a bounded set without holding up the library's first paint. Apple
    /// Music artwork is intentionally placed first by callers because its CDN
    /// tends to have a colder first response than Spotify's.
    func prefetch(_ urls: [URL], maxConcurrent: Int = 6) async {
        let prefetchGeneration = generation
        var seen = Set<URL>()
        let pending = urls.filter {
            seen.insert($0).inserted && image(for: $0) == nil
        }
        guard !pending.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var index = 0
            let concurrency = max(1, min(maxConcurrent, pending.count))
            while index < concurrency {
                let url = pending[index]
                group.addTask { [weak self] in
                    _ = await self?.load(
                        url,
                        expectedGeneration: prefetchGeneration
                    )
                }
                index += 1
            }
            for await _ in group {
                if index < pending.count, generation == prefetchGeneration {
                    let url = pending[index]
                    group.addTask { [weak self] in
                        _ = await self?.load(
                            url,
                            expectedGeneration: prefetchGeneration
                        )
                    }
                    index += 1
                }
            }
        }
    }

    private func remember(_ image: UIImage, for url: URL, encodedByteCount: Int) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? encodedByteCount
        images.setObject(image, forKey: url as NSURL, cost: cost)
    }

    private nonisolated static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data)
        }.value
    }

    private func fetch(_ url: URL) async -> Data? {
        if let task = inFlight[url] { return await task.value }

        let task = Task<Data?, Never> {
            let host = url.host?.lowercased() ?? ""
            let isAppleCDN = host == "mzstatic.com"
                || host.hasSuffix(".mzstatic.com")
                || host == "apple.com"
                || host.hasSuffix(".apple.com")
            let attempts = isAppleCDN ? 3 : 2

            for attempt in 0..<attempts {
                guard !Task.isCancelled else { return nil }
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = isAppleCDN ? 45 : 30
                request.setValue("image/*", forHTTPHeaderField: "Accept")

                do {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        return nil
                    }
                    if (200..<300).contains(http.statusCode),
                       http.mimeType?.lowercased().hasPrefix("image/") != false,
                       data.count <= 12 * 1_024 * 1_024 {
                        return data
                    }
                    // A missing/forbidden image is authoritative. Retry only
                    // throttles, timeouts, and transient server failures.
                    if (400..<500).contains(http.statusCode),
                       http.statusCode != 408,
                       http.statusCode != 429 {
                        return nil
                    }
                } catch {
                    guard !Task.isCancelled else { return nil }
                }

                if attempt + 1 < attempts {
                    try? await Task.sleep(
                        for: .milliseconds(250 * (attempt + 1))
                    )
                }
            }
            return nil
        }
        inFlight[url] = task
        let data = await task.value
        inFlight[url] = nil
        return data
    }

    private func refresh(
        _ url: URL,
        expectedGeneration: Int
    ) async {
        guard generation == expectedGeneration else { return }
        let diskGeneration = await ArtworkDiskCache.shared.currentGeneration()
        guard let data = await fetch(url),
              let image = await Self.decode(data),
              generation == expectedGeneration else { return }
        await ArtworkDiskCache.shared.store(data, for: url, generation: diskGeneration)
        guard generation == expectedGeneration else { return }
        remember(image, for: url, encodedByteCount: data.count)
    }
}

/// Async artwork that never drops a successfully decoded image back to a loading
/// placeholder when its surrounding SwiftUI view is refreshed.
struct CachedArtworkImage<Placeholder: View>: View {
    private struct Loaded {
        let url: URL
        let image: UIImage
    }

    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loaded: Loaded?
    @State private var loadingURL: URL?

    private var image: UIImage? {
        guard let url else { return nil }
        if loaded?.url == url { return loaded?.image }
        if let cached = ArtworkImageCache.shared.image(for: url) {
            return cached
        }
        // Keep the prior decoded image in place while a replacement URL loads.
        // The task clears it if the new URL genuinely fails, avoiding both a
        // placeholder flash and a permanently incorrect cover.
        return loaded?.image
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                loaded = nil
                loadingURL = nil
                return
            }
            loadingURL = url
            defer {
                if loadingURL == url { loadingURL = nil }
            }
            if let image = ArtworkImageCache.shared.image(for: url) {
                loaded = Loaded(url: url, image: image)
            } else if let image = await ArtworkImageCache.shared.load(url),
                      !Task.isCancelled {
                loaded = Loaded(url: url, image: image)
            } else if !Task.isCancelled, loaded?.url != url {
                loaded = nil
            }
        }
    }
}

/// One consistent album/playlist cover everywhere: always a square, always clipped
/// to a rounded rect, never bleeding past its bounds. The image is drawn as an
/// overlay on a fixed-size surface and `.clipped()` before the corner mask, so a
/// `.fill` image can't stretch into neighbouring cells (the leak we kept hitting).
///
/// Pass `size` for a fixed square (rows); omit it for a flexible square that fills
/// its grid column.
struct CoverArt: View {
    @Environment(ThemeStore.self) private var theme
    let url: URL?
    var size: CGFloat? = nil
    var corner: CGFloat = Theme.Radius.sm
    var placeholder: String = "music.note"
    /// Glyph size for the placeholder; scales with the cover when fixed.
    var placeholderScale: CGFloat = 0.34

    var body: some View {
        Group {
            if let size {
                surface.frame(width: size, height: size)
            } else {
                surface.aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var surface: some View {
        Rectangle()
            .fill(theme.palette.surface)
            .overlay {
                GeometryReader { geo in
                    CachedArtworkImage(url: url) {
                        Image(systemName: placeholder)
                            .font(.system(size: geo.size.width * placeholderScale))
                            .foregroundStyle(theme.palette.textMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
            }
            .clipped()
    }
}
