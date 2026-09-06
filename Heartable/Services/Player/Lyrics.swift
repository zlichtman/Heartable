import Foundation

/// LRCLIB lyrics: a free, no-auth lyric database keyed by track/artist/album/duration.
///
///   GET https://lrclib.net/api/get
///     ?track_name=<title>&artist_name=<artist>&album_name=<album>&duration=<seconds>
///
/// Returns `syncedLyrics` (LRC text) and/or `plainLyrics`. A 404 means "not in the
/// database", which is common and not worth surfacing — every error path resolves
/// to empty so the UI shows a quiet placeholder.

/// One timestamped lyric line parsed from an LRC body.
struct SyncedLine: Sendable, Identifiable {
    let timeMs: Int
    let text: String
    var id: Int { timeMs }
}

/// Networking + parsing for LRCLIB, with a tiny in-memory cache. Actor-isolated so
/// the cache is safe under strict concurrency.
actor LyricsService {
    static let shared = LyricsService()

    private struct Response: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private var cache: [String: (synced: [SyncedLine], plain: String?)] = [:]

    private static func key(track: String, artist: String, album: String?, durationMs: Int) -> String {
        [
            track.lowercased(),
            artist.lowercased(),
            (album ?? "").lowercased(),
            String(durationMs / 1000),
        ].joined(separator: "|")
    }

    /// Fetch lyrics. Returns parsed synced lines (sorted) plus plain text as a
    /// fallback. Any failure (including 404) resolves to `([], nil)`.
    func fetch(
        track: String,
        artist: String,
        album: String?,
        durationMs: Int
    ) async -> (synced: [SyncedLine], plain: String?) {
        let trimmedTrack = track.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrack.isEmpty, !trimmedArtist.isEmpty else { return ([], nil) }

        let cacheKey = Self.key(track: trimmedTrack, artist: trimmedArtist, album: album, durationMs: durationMs)
        if let hit = cache[cacheKey] { return hit }

        guard let url = Self.buildURL(track: trimmedTrack, artist: trimmedArtist, album: album, durationMs: durationMs) else {
            return ([], nil)
        }

        do {
            let resp: Response = try await HTTPClient.getJSON(url, headers: ["Lrclib-Client": "Heartable"])
            let synced = resp.syncedLyrics.map(Self.parseLRC) ?? []
            let plain = resp.plainLyrics.flatMap { $0.isEmpty ? nil : $0 }
            let result = (synced: synced, plain: plain)
            cache[cacheKey] = result
            return result
        } catch {
            let empty: (synced: [SyncedLine], plain: String?) = ([], nil)
            // A timeout is not evidence that lyrics do not exist. Only cache an
            // authoritative miss, so opening the player later can recover.
            if case HTTPClient.Failure.status(404) = error { cache[cacheKey] = empty }
            return empty
        }
    }

    private static func buildURL(track: String, artist: String, album: String?, durationMs: Int) -> URL? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let album, !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if durationMs > 0 {
            items.append(URLQueryItem(name: "duration", value: String(durationMs / 1000)))
        }
        comps?.queryItems = items
        return comps?.url
    }

    /// Parse an LRC body. Lines look like `[mm:ss.xx]text`; a single line may carry
    /// multiple leading timestamps, each emitted as its own `SyncedLine`. Result is
    /// sorted ascending by time.
    static func parseLRC(_ raw: String) -> [SyncedLine] {
        var out: [SyncedLine] = []
        for line in raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            var rest = Substring(line)
            var stamps: [Int] = []
            while let stamp = takeLeadingStamp(&rest) {
                stamps.append(stamp)
            }
            guard !stamps.isEmpty else { continue }
            let text = rest.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for ms in stamps {
                out.append(SyncedLine(timeMs: ms, text: text))
            }
        }
        return out.sorted { $0.timeMs < $1.timeMs }
    }

    /// Consume one `[mm:ss(.xx)]` prefix from `s`, returning its ms value and
    /// advancing `s` past it. Returns nil if `s` does not start with a timestamp.
    private static func takeLeadingStamp(_ s: inout Substring) -> Int? {
        guard s.first == "[",
              let close = s.firstIndex(of: "]") else { return nil }
        let inner = s[s.index(after: s.startIndex)..<close]
        let parts = inner.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]) else { return nil }
        let secParts = parts[1].split(separator: ".")
        guard let seconds = Int(secParts[0]) else { return nil }
        var ms = (minutes * 60 + seconds) * 1000
        if secParts.count > 1 {
            let frac = String(secParts[1].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            if let h = Int(frac) { ms += h }
        }
        s = s[s.index(after: close)...]
        return ms
    }
}

/// View-facing lyrics state. Loads for the current track, dedupes by `uri`, and
/// exposes the synced/plain results plus a helper to find the active line.
@MainActor
@Observable
final class LyricsModel {
    private(set) var synced: [SyncedLine] = []
    private(set) var plain: String?
    private(set) var loading = false

    private var loadedURI: String?
    private var loadTask: Task<Void, Never>?

    init(synced: [SyncedLine] = [], plain: String? = nil) {
        self.synced = synced
        self.plain = plain
    }

    nonisolated static func previewIndices(active: Int?, count: Int) -> Range<Int> {
        let start = min(max(0, (active ?? 0) - 1), max(0, count - 3))
        return start..<min(count, start + 3)
    }

    /// Load lyrics for the given now-playing track. No-op if the same `uri` is
    /// already loaded or in flight.
    func load(for now: PlayerStore.Now) {
        guard now.uri != loadedURI else { return }
        loadTask?.cancel()
        loadedURI = now.uri
        synced = []
        plain = nil
        loading = true

        let track = now.name
        let artist = now.artist
        let durationMs = now.durationMs
        let uri = now.uri

        loadTask = Task {
            let result = await LyricsService.shared.fetch(
                track: track,
                artist: artist,
                album: nil,
                durationMs: durationMs
            )
            // Drop if the track changed while we were fetching.
            guard !Task.isCancelled, uri == self.loadedURI else { return }
            self.synced = result.synced
            self.plain = result.plain
            self.loading = false
        }
    }

    /// Index of the last synced line whose `timeMs` is <= `positionMs`, or nil if
    /// playback is before the first line / there are no synced lines.
    func currentIndex(positionMs: Int) -> Int? {
        guard !synced.isEmpty else { return nil }
        var result: Int?
        for (i, line) in synced.enumerated() {
            if line.timeMs <= positionMs { result = i } else { break }
        }
        return result
    }
}
