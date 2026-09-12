import Foundation
import Supabase

/// CSV-import path for backups. Parses a previously exported (or hand-built) CSV
/// in the Heartable export shape `playlist,name,artist,album,uri` and writes it
/// back into the snapshot tables as a new `library_snapshots` row plus its
/// `snapshot_playlists`/`snapshot_tracks` children. Rows with an empty `playlist`
/// column are treated as liked songs and go to `snapshot_liked_tracks`.
///
/// All writes use the authenticated Supabase client; RLS lets the owner insert
/// rows it owns (owner = auth.uid()). Lives in its own file so it can extend
/// `BackendAPI` without touching the shared `BackendAPI.swift`/`DTOs.swift`.

/// One parsed CSV row in the Heartable export shape. Optional columns tolerate a
/// header that omits them; `uri` is the only field the importer needs.
struct ImportedRow: Sendable {
    var playlist: String
    var name: String?
    var artist: String?
    var album: String?
    var uri: String
    var albumArtURL: String? = nil
    var playlistImageURL: String? = nil
    var durationMS: Int? = nil

    init(playlist: String, name: String?, artist: String?, album: String?, uri: String,
         albumArtURL: String? = nil, playlistImageURL: String? = nil, durationMS: Int? = nil) {
        self.playlist = playlist
        self.name = name
        self.artist = artist
        self.album = album
        self.uri = uri
        self.albumArtURL = albumArtURL
        self.playlistImageURL = playlistImageURL
        self.durationMS = durationMS
    }

    init(track: UnifiedTrack) {
        self.init(playlist: "", name: track.name, artist: track.artistNames,
                  album: track.album, uri: track.uri,
                  albumArtURL: track.albumArt?.absoluteString, durationMS: track.durationMs)
    }
}

struct CapturedPlaylist: Sendable {
    let name: String
    let rows: [ImportedRow]
    var sourceID: String = ""
    var imageURL: String? = nil

    init(name: String, rows: [ImportedRow]) {
        self.name = name
        self.rows = rows
        imageURL = rows.compactMap(\.playlistImageURL).first
    }

    init(playlist: UnifiedPlaylist, tracks: [UnifiedTrack]) {
        name = playlist.name
        rows = tracks.map(ImportedRow.init(track:))
        sourceID = playlist.playlistID
        imageURL = playlist.image?.absoluteString ?? tracks.compactMap(\.albumArt).first?.absoluteString
    }
}

/// RFC-4180 CSV parser: handles quoted fields, escaped quotes (`""`), and commas
/// or newlines embedded inside quotes. Header-driven so columns can appear in any
/// order and optional columns may be missing. Whitespace around unquoted values
/// is trimmed.
enum CSVImportParser {
    /// Snapshot metadata is distinct from track added-at timestamps. Never infer
    /// capture time from the file's creation/modification date after download.
    static func snapshotDate(_ text: String) throws -> Date? {
        let records = parseRecords(text, delimiter: sniffDelimiter(text))
        guard let header = records.first,
              let index = header.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "snapshot_created_at" }) else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ordinary = ISO8601DateFormatter()
        var dates = Set<Date>()
        for row in records.dropFirst() {
            guard index < row.count else { continue }
            let raw = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            guard let date = fractional.date(from: raw) ?? ordinary.date(from: raw) else {
                throw BackendError.message("The backup contains an invalid creation date.")
            }
            dates.insert(date)
        }
        guard dates.count <= 1 else { throw BackendError.message("The CSV contains more than one backup creation date.") }
        return dates.first
    }
    /// Parse raw CSV text into `ImportedRow`s. Returns an empty array if there is
    /// no data row or no usable `uri` column. Rows missing a `uri` value are skipped.
    static func parse(_ text: String) -> [ImportedRow] {
        let records = parseRecords(text, delimiter: sniffDelimiter(text))
        guard records.count >= 1 else { return [] }

        // Header → column index. Lowercased + trimmed for tolerant matching.
        let header = records[0].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func index(of names: [String]) -> Int? {
            for n in names { if let i = header.firstIndex(of: n) { return i } }
            return nil
        }
        let playlistIdx = index(of: ["playlist", "playlist name", "playlist_name"])
        let nameIdx = index(of: ["name", "track", "track_name", "track name", "title", "song", "song name"])
        let artistIdx = index(of: ["artist", "artist_name", "artist name", "artist name(s)", "artists", "artist(s)"])
        let albumIdx = index(of: ["album", "album_name", "album name"])
        let artworkIdx = index(of: ["album_art_url", "artwork_url", "album art url"])
        let playlistImageIdx = index(of: ["playlist_image_url", "playlist image url"])
        let durationIdx = index(of: ["duration_ms", "duration ms"])
        // Accept the common spellings used by Heartable, Exportify, TuneMyMusic, etc.
        let uriIdx = index(of: ["uri", "spotify_track_uri", "spotify uri", "track uri",
                                "spotify track uri", "track_uri", "spotify_uri"])
        // Fallback: a column holding an open.spotify.com/track/... or spotify:track:
        // link we can turn into a track uri.
        let urlIdx = index(of: ["url", "track url", "spotify url", "song url", "link",
                                "external url", "external_urls", "spotify_url", "track_url"])

        // Without a uri (or a derivable url) there is nothing addressable to restore.
        guard uriIdx != nil || urlIdx != nil else { return [] }

        func field(_ row: [String], _ idx: Int?) -> String? {
            guard let idx, idx < row.count else { return nil }
            let v = row[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }

        // Normalize any Spotify track reference to a `spotify:track:<id>` uri.
        func trackURI(_ raw: String?) -> String? {
            guard let raw, !raw.isEmpty else { return nil }
            if raw.hasPrefix("spotify:track:") { return raw }
            if let colon = raw.firstIndex(of: ":"),
               ProviderID(rawValue: String(raw[..<colon])) != nil,
               raw.index(after: colon) < raw.endIndex {
                return raw
            }
            // open.spotify.com/track/<id>?... -> spotify:track:<id>
            if let r = raw.range(of: "track/") {
                let tail = raw[r.upperBound...]
                let id = tail.prefix { $0.isLetter || $0.isNumber }
                if !id.isEmpty { return "spotify:track:\(id)" }
            }
            // A bare 22-char base62 id.
            if raw.count == 22, raw.allSatisfy({ $0.isLetter || $0.isNumber }) {
                return "spotify:track:\(raw)"
            }
            return nil
        }

        var rows: [ImportedRow] = []
        for record in records.dropFirst() {
            // Skip fully blank lines.
            if record.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }
            guard let uri = trackURI(field(record, uriIdx)) ?? trackURI(field(record, urlIdx)) else { continue }
            rows.append(ImportedRow(
                playlist: field(record, playlistIdx) ?? "",
                name: field(record, nameIdx),
                artist: field(record, artistIdx),
                album: field(record, albumIdx),
                uri: uri,
                albumArtURL: field(record, artworkIdx),
                playlistImageURL: field(record, playlistImageIdx),
                durationMS: field(record, durationIdx).flatMap(Int.init)
            ))
        }
        return rows
    }

    /// The header row's column names (trimmed), for diagnostics when a parse finds
    /// no usable rows — so the UI can show what columns the file actually had.
    static func headerColumns(_ text: String) -> [String] {
        guard let first = parseRecords(text, delimiter: sniffDelimiter(text)).first else { return [] }
        return first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Pick the field delimiter by counting unquoted occurrences in the first line.
    /// Spotify/Exportify use commas; many European/Excel "Save as CSV" exports use
    /// semicolons; some tools use tabs. Defaults to comma.
    private static func sniffDelimiter(_ text: String) -> Character {
        var s = text
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }     // ignore a leading BOM
        s = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let firstLine = s.prefix { $0 != "\n" }
        var comma = 0, semi = 0, tab = 0
        var inQuotes = false
        for c in firstLine {
            if c == "\"" { inQuotes.toggle() }
            else if !inQuotes {
                if c == "," { comma += 1 }
                else if c == ";" { semi += 1 }
                else if c == "\t" { tab += 1 }
            }
        }
        if semi > comma && semi >= tab { return ";" }
        if tab > comma && tab > semi { return "\t" }
        return ","
    }

    /// Split CSV text into records of fields, honoring quotes per RFC 4180. Strips a
    /// leading UTF-8 BOM (Exportify / Excel exports include one, which would otherwise
    /// mangle the first header cell so its column never matches).
    private static func parseRecords(_ text: String, delimiter: Character = ",") -> [[String]] {
        var records: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        var src = text
        if src.hasPrefix("\u{FEFF}") { src.removeFirst() }
        // Normalize line endings FIRST: Swift treats "\r\n" as a single Character
        // grapheme, so per-character "\r"/"\n" checks miss it and a CRLF file
        // (Excel / Exportify / our own export) collapses into one record. Fold to LF.
        src = src.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let scalars = Array(src)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    // Lookahead for an escaped quote ("").
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                field.append(c)
                i += 1
            } else {
                if c == "\"" {
                    inQuotes = true
                    i += 1
                } else if c == delimiter {
                    record.append(field)
                    field = ""
                    i += 1
                } else if c == "\r" {
                    // Treat CR / CRLF as one line terminator.
                    record.append(field)
                    records.append(record)
                    field = ""
                    record = []
                    if i + 1 < scalars.count, scalars[i + 1] == "\n" { i += 2 } else { i += 1 }
                } else if c == "\n" {
                    record.append(field)
                    records.append(record)
                    field = ""
                    record = []
                    i += 1
                } else {
                    field.append(c)
                    i += 1
                }
            }
        }
        // Flush the trailing field/record if the file did not end with a newline.
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}

// MARK: - Insert payloads (new tables, owned by this importer)

/// Insert payload for `library_snapshots` (owner + user_id stamped from session).
private struct SnapshotInsertDTO: Codable, Sendable {
    var owner: UUID
    var userId: String
    var name: String
    var playlistCount: Int
    var trackCount: Int
    var likedCount: Int
    var providers: [String]
    var createdAt: String? = nil

    enum CodingKeys: String, CodingKey {
        case owner
        case userId = "user_id"
        case name
        case playlistCount = "playlist_count"
        case trackCount = "track_count"
        case likedCount = "liked_count"
        case providers
        case createdAt = "created_at"
    }
}

/// Insert payload for `snapshot_playlists`. Imported playlists have no Spotify id
/// (a CSV only carries names), so `spotify_playlist_id` is sent as "" to satisfy
/// the column's NOT NULL constraint explicitly rather than relying on its default.
struct SnapshotPlaylistInsertDTO: Codable, Sendable {
    var snapshotId: UUID
    var spotifyPlaylistId: String = ""
    var name: String
    var trackCount: Int
    var imageUrl: String? = nil
    var providerId: String = ProviderID.spotify.rawValue

    enum CodingKeys: String, CodingKey {
        case snapshotId = "snapshot_id"
        case spotifyPlaylistId = "spotify_playlist_id"
        case name
        case trackCount = "track_count"
        case imageUrl = "image_url"
        case providerId = "provider_id"
    }
}

/// Insert payload for `snapshot_tracks`.
struct SnapshotTrackInsertDTO: Codable, Sendable {
    var snapshotPlaylistId: UUID
    var spotifyTrackUri: String
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var position: Int
    var albumArtUrl: String? = nil
    var durationMs: Int? = nil
    var providerId: String = ProviderID.spotify.rawValue

    enum CodingKeys: String, CodingKey {
        case snapshotPlaylistId = "snapshot_playlist_id"
        case spotifyTrackUri = "spotify_track_uri"
        case trackName = "track_name"
        case artistName = "artist_name"
        case albumName = "album_name"
        case position
        case albumArtUrl = "album_art_url"
        case durationMs = "duration_ms"
        case providerId = "provider_id"
    }
}

/// Insert payload for `snapshot_liked_tracks`.
struct SnapshotLikedTrackInsertDTO: Codable, Sendable {
    var snapshotId: UUID
    var spotifyTrackUri: String
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var position: Int
    var albumArtUrl: String? = nil
    var durationMs: Int? = nil
    var providerId: String = ProviderID.spotify.rawValue

    enum CodingKeys: String, CodingKey {
        case snapshotId = "snapshot_id"
        case spotifyTrackUri = "spotify_track_uri"
        case trackName = "track_name"
        case artistName = "artist_name"
        case albumName = "album_name"
        case position
        case albumArtUrl = "album_art_url"
        case durationMs = "duration_ms"
        case providerId = "provider_id"
    }
}

/// Lightweight rows used to derive provider badges for an entire backup page in
/// three requests instead of three requests per snapshot.
private struct SnapshotURIRowDTO: Decodable, Sendable {
    var snapshotId: UUID
    var spotifyTrackUri: String

    enum CodingKeys: String, CodingKey {
        case snapshotId = "snapshot_id"
        case spotifyTrackUri = "spotify_track_uri"
    }
}

private struct SnapshotPlaylistRefDTO: Decodable, Sendable {
    var id: UUID
    var snapshotId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case snapshotId = "snapshot_id"
    }
}

private struct PlaylistURIRowDTO: Decodable, Sendable {
    var snapshotPlaylistId: UUID
    var spotifyTrackUri: String

    enum CodingKeys: String, CodingKey {
        case snapshotPlaylistId = "snapshot_playlist_id"
        case spotifyTrackUri = "spotify_track_uri"
    }
}

/// Outcome of a CSV import, surfaced to the UI for a success banner.
struct ImportSnapshotResult: Sendable {
    var snapshotID: UUID
    var playlistCount: Int
    var trackCount: Int
    var likedCount: Int
}

extension BackendAPI {
    /// Import a parsed CSV into a brand-new snapshot. Inserts the
    /// `library_snapshots` row (owner = auth.uid(), user_id = the user's id string),
    /// groups rows by `playlist` into `snapshot_playlists` + their `snapshot_tracks`
    /// (position by row order), and routes rows with an empty `playlist` to
    /// `snapshot_liked_tracks`. Throws a friendly `BackendError` on failure.
    @discardableResult
    func importSnapshotFromCSV(name: String, rows: [ImportedRow], createdAt: Date, expectedUserID: UUID) async throws -> ImportSnapshotResult {
        guard !rows.isEmpty else {
            throw BackendError.message("No tracks found in that CSV.")
        }

        // Partition into playlists (ordered, preserving first-seen order) and liked.
        var playlistOrder: [String] = []
        var byPlaylist: [String: [ImportedRow]] = [:]
        var liked: [ImportedRow] = []
        for row in rows {
            let key = row.playlist.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                liked.append(row)
            } else {
                if byPlaylist[key] == nil { playlistOrder.append(key) }
                byPlaylist[key, default: []].append(row)
            }
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshotName = trimmedName.isEmpty ? "Imported snapshot" : trimmedName
        let playlists = playlistOrder.map { CapturedPlaylist(name: $0, rows: byPlaylist[$0] ?? []) }

        do {
            return try await insertSnapshot(
                name: snapshotName,
                providerIDs: Array(Set(rows.compactMap {
                    ProviderID(rawValue: String($0.uri.prefix { $0 != ":" }))?.rawValue
                })).sorted(),
                playlists: playlists,
                liked: liked,
                expectedUserID: expectedUserID,
                createdAt: createdAt
            )
        } catch let error as BackendError {
            throw error
        } catch {
            throw BackendError.message("Import failed. Please try again.")
        }
    }

    /// Capture a fresh snapshot of the live library by reading each selected
    /// connected provider through its `MusicProvider` adapter. Each selected
    /// service contributes its playlists (with tracks) and liked songs to one
    /// snapshot, and the snapshot is tagged with only the providers that actually
    /// contributed content (a selected-but-empty service is left off the label).
    /// Each track's unified `uri` goes into the `spotify_track_uri` column (a
    /// generic URI column); only Spotify URIs are restorable, but every service
    /// round-trips via CSV export.
    @discardableResult
    func captureSnapshot(providerIDs: [ProviderID], name: String? = nil) async throws -> ImportSnapshotResult {
        try await captureSnapshot(
            providerIDs: providerIDs,
            name: name,
            userID: nil
        )
    }

    /// Account-bound form used by scheduled work. A backup can spend minutes
    /// traversing large libraries; if the user signs out during that traversal,
    /// never insert the old account's tracks into the next session.
    @discardableResult
    func captureSnapshot(
        providerIDs: [ProviderID],
        name: String? = nil,
        userID expectedUserID: UUID?
    ) async throws -> ImportSnapshotResult {
        guard !providerIDs.isEmpty else {
            throw BackendError.message("Pick at least one connected service to back up.")
        }
        guard let ownerID = AccountSessionStore.currentOwnerID,
              expectedUserID == nil || expectedUserID == ownerID else {
            throw BackendError.notSignedIn
        }

        var playlists: [CapturedPlaylist] = []
        var liked: [ImportedRow] = []
        // A snapshot's label must list only the services that actually landed in
        // it. A selected service that returns nothing (not truly connected, empty
        // library) must not be tagged, so track contribution as we go and record
        // only providers that added at least one track. A service whose read
        // FAILED is different: a backup that claims to cover it with zero rows
        // would later read as deletions, so the whole capture stops instead.
        var capturedProviderIDs: [ProviderID] = []

        for id in providerIDs {
            guard AccountSessionStore.currentOwnerID == ownerID else {
                throw BackendError.notSignedIn
            }
            let provider = ProviderRegistry.provider(for: id)
            let strict = Self.strictReadProviders.contains(id)
            var contributed = false

            // Liked songs first. On Spotify this is the read most exposed to a
            // rate-limit cooldown; it must never be recorded as zero because the
            // playlist traversal ahead of it spent the request budget.
            let likedRead = await provider.readLikedTracks(limit: 10_000)
            guard AccountSessionStore.currentOwnerID == ownerID else {
                throw BackendError.notSignedIn
            }
            switch likedRead {
            case .success(let likedTracks):
                if !likedTracks.isEmpty {
                    liked.append(contentsOf: likedTracks.map(ImportedRow.init(track:)))
                    contributed = true
                }
            case .unavailable:
                if strict { throw await Self.unreadable(id, what: "liked songs") }
            }

            let playlistsRead = await provider.readPlaylists()
            guard AccountSessionStore.currentOwnerID == ownerID else {
                throw BackendError.notSignedIn
            }
            switch playlistsRead {
            case .success(let catalog):
                for pl in catalog {
                    guard AccountSessionStore.currentOwnerID == ownerID else {
                        throw BackendError.notSignedIn
                    }
                    let tracksRead = await provider.readPlaylistTracks(pl.playlistID)
                    guard AccountSessionStore.currentOwnerID == ownerID else {
                        throw BackendError.notSignedIn
                    }
                    switch tracksRead {
                    case .success(let tracks):
                        guard !tracks.isEmpty else { continue }
                        playlists.append(CapturedPlaylist(playlist: pl, tracks: tracks))
                        contributed = true
                    case .unavailable:
                        if strict { throw await Self.unreadable(id, what: "the playlist “\(pl.name)”") }
                    }
                }
            case .unavailable:
                if strict { throw await Self.unreadable(id, what: "playlists") }
            }
            if contributed { capturedProviderIDs.append(id) }
        }

        guard !playlists.isEmpty || !liked.isEmpty else {
            throw BackendError.message("Nothing to back up from the selected services.")
        }

        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshotName = trimmed.isEmpty ? BackupName.timestamp() : try BackupName.validated(trimmed)
        do {
            return try await insertSnapshot(
                name: snapshotName,
                providerIDs: capturedProviderIDs.map(\.rawValue),
                playlists: playlists,
                liked: liked,
                expectedUserID: ownerID
            )
        } catch let error as BackendError {
            throw error
        } catch {
            throw BackendError.message("Backup failed. Please try again.")
        }
    }

    /// Adapters with typed reads answer `.unavailable` only for a failed read,
    /// so a backup must not claim to cover them. Legacy adapters answer
    /// `.unavailable` for an empty collection too, so for them it means empty.
    static let strictReadProviders: Set<ProviderID> = [.spotify, .apple]

    private static func unreadable(_ id: ProviderID, what: String) async -> BackendError {
        let label = ProviderCatalog.entry(id)?.label ?? id.rawValue
        if id == .spotify, let resume = await SpotifyReadBackoff.shared.resumeDate() {
            let time = resume.formatted(date: .omitted, time: .shortened)
            return .message("Spotify is limiting requests until \(time), so \(what) couldn’t be read. The backup was not saved; it will retry.")
        }
        return .message("\(label) couldn’t be read (\(what)). The backup was not saved so it never records songs as missing; try again in a moment.")
    }

    /// Provider tag for a snapshot row, from the `{providerID}:` prefix of its URI.
    static func providerRawValue(forURI uri: String) -> String {
        let prefix = String(uri.prefix { $0 != ":" })
        return ProviderID(rawValue: prefix)?.rawValue ?? ProviderID.spotify.rawValue
    }

    /// The distinct set of services actually present in a snapshot, derived from
    /// the provider prefix of each stored track/liked `uri` (`"{providerID}:..."`).
    ///
    /// This is the source of truth for a snapshot's service label: it reflects
    /// what was really captured, not what was selected at capture time. It also
    /// corrects legacy snapshots whose denormalized `providers` column was written
    /// with the full selected set (including services that contributed nothing).
    /// Only the `uri` columns are fetched, so the derivation stays light. Returns
    /// an empty array when a snapshot has no addressable rows.
    func snapshotProviderIDs(snapshotID: UUID) async -> [ProviderID] {
        await snapshotProviderIDs(snapshotIDs: [snapshotID])[snapshotID] ?? []
    }

    /// Resolve provider sets for many snapshots in a fixed number of round trips.
    /// The old UI called `snapshotProviderIDs(snapshotID:)` for every card, which
    /// became an increasingly expensive N+1 fan-out as backup history grew.
    func snapshotProviderIDs(snapshotIDs: [UUID]) async -> [UUID: [ProviderID]] {
        guard !snapshotIDs.isEmpty else { return [:] }
        let client = SupabaseClientProvider.shared
        let values = snapshotIDs.map(\.uuidString)

        async let likedFetch: [SnapshotURIRowDTO] = (try? await client
            .from("snapshot_liked_tracks")
            .select("snapshot_id, spotify_track_uri")
            .in("snapshot_id", values: values)
            .execute()
            .value) ?? []

        let playlistRefs: [SnapshotPlaylistRefDTO] = (try? await client
            .from("snapshot_playlists")
            .select("id, snapshot_id")
            .in("snapshot_id", values: values)
            .execute()
            .value) ?? []

        let trackRows: [PlaylistURIRowDTO]
        if playlistRefs.isEmpty {
            trackRows = []
        } else {
            trackRows = (try? await client
                .from("snapshot_tracks")
                .select("snapshot_playlist_id, spotify_track_uri")
                .in("snapshot_playlist_id", values: playlistRefs.map { $0.id.uuidString })
                .execute()
                .value) ?? []
        }
        let likedRows = await likedFetch
        let snapshotForPlaylist = Dictionary(
            uniqueKeysWithValues: playlistRefs.map { ($0.id, $0.snapshotId) }
        )

        var urisBySnapshot: [UUID: [String]] = [:]
        for row in likedRows {
            urisBySnapshot[row.snapshotId, default: []].append(row.spotifyTrackUri)
        }
        for row in trackRows {
            guard let snapshotID = snapshotForPlaylist[row.snapshotPlaylistId] else { continue }
            urisBySnapshot[snapshotID, default: []].append(row.spotifyTrackUri)
        }

        var result: [UUID: [ProviderID]] = [:]
        for snapshotID in snapshotIDs {
            var seen = Set<ProviderID>()
            result[snapshotID] = urisBySnapshot[snapshotID, default: []].compactMap { uri in
                let prefix = uri.prefix { $0 != ":" }
                guard let id = ProviderID(rawValue: String(prefix)),
                      seen.insert(id).inserted else { return nil }
                return id
            }
        }
        return result
    }

    /// Shared writer for both CSV import and live capture: inserts the
    /// `library_snapshots` row, then each playlist + `snapshot_tracks` (position by
    /// order), then liked songs into `snapshot_liked_tracks`. Liked rows use the
    /// playlist name only for grouping at the call site; here playlists arrive
    /// already grouped and `liked` is the empty-playlist bucket.
    private func insertSnapshot(
        name: String,
        providerIDs: [String],
        playlists: [CapturedPlaylist],
        liked: [ImportedRow],
        expectedUserID: UUID? = nil,
        createdAt: Date? = nil
    ) async throws -> ImportSnapshotResult {
        let client = SupabaseClientProvider.shared
        guard let uid = try? await client.auth.session.user.id,
              expectedUserID == nil || expectedUserID == uid else {
            throw BackendError.notSignedIn
        }

        let playlistCount = playlists.count
        let trackCount = playlists.reduce(0) { $0 + $1.rows.count }
        let likedCount = liked.count

        // 1) Snapshot row — read back its id.
        let snapInsert = SnapshotInsertDTO(
            owner: uid,
            userId: uid.uuidString,
            name: name,
            playlistCount: playlistCount,
            trackCount: trackCount,
            likedCount: likedCount,
            providers: providerIDs,
            createdAt: createdAt.map {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter.string(from: $0)
            }
        )
        let inserted: [IdRowDTO] = try await client
            .from("library_snapshots")
            .insert(snapInsert)
            .select("id")
            .execute()
            .value
        guard let snapshotID = inserted.first?.id else {
            throw BackendError.message("Snapshot insert returned no row.")
        }
        guard expectedUserID == nil
                || AccountSessionStore.currentOwnerID == expectedUserID else {
            throw BackendError.notSignedIn
        }

        // The child inserts are not one transaction. A snapshot row without its
        // songs would later count as a completed baseline and read as an empty
        // library, so any failure below removes the parent again.
        do {
            try await insertChildren(of: snapshotID, playlists: playlists, liked: liked,
                                     expectedUserID: expectedUserID, client: client)
        } catch {
            _ = await BackendAPI.shared.deleteSnapshot(id: snapshotID)
            throw error
        }

        return ImportSnapshotResult(
            snapshotID: snapshotID,
            playlistCount: playlistCount,
            trackCount: trackCount,
            likedCount: likedCount
        )
    }

    /// PostgREST accepts large bodies, but one multi-megabyte insert of ten
    /// thousand liked songs is the request most likely to time out; keep every
    /// child insert to a bounded batch.
    private static let insertBatchSize = 500

    private func insertChildren(
        of snapshotID: UUID,
        playlists: [CapturedPlaylist],
        liked: [ImportedRow],
        expectedUserID: UUID?,
        client: SupabaseClient
    ) async throws {
        // 2) Each playlist + its tracks (position by row order).
        for pl in playlists {
            guard expectedUserID == nil
                    || AccountSessionStore.currentOwnerID == expectedUserID else {
                throw BackendError.notSignedIn
            }
            let plInsert = SnapshotPlaylistInsertDTO(
                snapshotId: snapshotID,
                spotifyPlaylistId: pl.sourceID,
                name: pl.name,
                trackCount: pl.rows.count,
                imageUrl: pl.imageURL,
                providerId: pl.rows.first.map { Self.providerRawValue(forURI: $0.uri) } ?? ProviderID.spotify.rawValue
            )
            let plInserted: [IdRowDTO] = try await client
                .from("snapshot_playlists")
                .insert(plInsert)
                .select("id")
                .execute()
                .value
            guard let plID = plInserted.first?.id else { continue }

            let trackPayload = pl.rows.enumerated().map { idx, r in
                SnapshotTrackInsertDTO(
                    snapshotPlaylistId: plID,
                    spotifyTrackUri: r.uri,
                    trackName: r.name,
                    artistName: r.artist,
                    albumName: r.album,
                    position: idx,
                    albumArtUrl: r.albumArtURL,
                    durationMs: r.durationMS,
                    providerId: Self.providerRawValue(forURI: r.uri)
                )
            }
            for batch in Self.batches(trackPayload) {
                try await client.from("snapshot_tracks").insert(batch).execute()
            }
        }

        // 3) Liked songs (empty-playlist rows).
        let likedPayload = liked.enumerated().map { idx, r in
            SnapshotLikedTrackInsertDTO(
                snapshotId: snapshotID,
                spotifyTrackUri: r.uri,
                trackName: r.name,
                artistName: r.artist,
                albumName: r.album,
                position: idx,
                albumArtUrl: r.albumArtURL,
                durationMs: r.durationMS,
                providerId: Self.providerRawValue(forURI: r.uri)
            )
        }
        for batch in Self.batches(likedPayload) {
            guard expectedUserID == nil
                    || AccountSessionStore.currentOwnerID == expectedUserID else {
                throw BackendError.notSignedIn
            }
            try await client.from("snapshot_liked_tracks").insert(batch).execute()
        }
    }

    static func batches<T>(_ rows: [T], size: Int = insertBatchSize) -> [[T]] {
        guard !rows.isEmpty else { return [] }
        return stride(from: 0, to: rows.count, by: max(1, size)).map { start in
            Array(rows[start..<min(start + max(1, size), rows.count)])
        }
    }
}
