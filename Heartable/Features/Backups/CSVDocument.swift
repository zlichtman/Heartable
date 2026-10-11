import SwiftUI
import UniformTypeIdentifiers

/// A `Transferable` CSV built from a snapshot's tracks. Fetched lazily when the
/// share sheet asks for the data. Optional artwork columns survive re-import.
///
/// The export writes every playlist's tracks, then appends liked songs with an
/// empty `playlist` column. That empty column is the documented liked-song marker
/// the importer reads (rows with no playlist → `snapshot_liked_tracks`), so an
/// exported CSV round-trips back into liked songs on re-import.
struct CSVDocument: Transferable {
    let snapshot: LibrarySnapshotDTO

    /// One CSV line: the source playlist name plus the track fields.
    struct Row: Sendable {
        let playlist: String
        let name: String?
        let artist: String?
        let album: String?
        let uri: String
        var albumArtURL: String? = nil
        var playlistImageURL: String? = nil
        var durationMS: Int? = nil
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { doc in
            // A partial read is an error, never a smaller file.
            let rows = try await Self.rows(for: doc.snapshot.id)
            return Data(Self.csv(from: rows, createdAt: doc.snapshot.createdAt).utf8)
        }
        .suggestedFileName { doc in
            let base = doc.snapshot.name?.isEmpty == false ? doc.snapshot.name! : "snapshot"
            let safe = base.map { $0.isLetter || $0.isNumber ? $0 : "-" }
            return "heartable-backup-" + String(safe) + ".csv"
        }
    }

    /// Gather every track across the snapshot's playlists, then append liked songs
    /// (empty `playlist` column so they re-import as liked, not as a playlist).
    static func rows(for snapshotID: UUID) async throws -> [Row] {
        async let playlistsFetch = BackendAPI.shared.requireSnapshotPlaylists(snapshotID: snapshotID)
        async let likedFetch = BackendAPI.shared.requireSnapshotLikedTracks(snapshotID: snapshotID)
        let playlists = try await playlistsFetch
        let playlistRows = try await fetchPlaylistRows(playlists, maxConcurrent: 6)
        var rows: [Row] = []
        for (index, label, tracks) in playlistRows.sorted(by: { $0.0 < $1.0 }) {
            for t in tracks {
                rows.append(Row(playlist: label, name: t.trackName, artist: t.artistName,
                                album: t.albumName, uri: t.spotifyTrackUri,
                                albumArtURL: t.albumArtUrl, playlistImageURL: playlists[index].imageUrl,
                                durationMS: t.durationMs))
            }
        }
        // Always include liked songs with an empty playlist column (the importer's
        // liked-song marker), so full snapshots export every track and round-trip.
        let liked = try await likedFetch
        for t in liked {
            rows.append(Row(playlist: "", name: t.trackName, artist: t.artistName,
                            album: t.albumName, uri: t.spotifyTrackUri,
                            albumArtURL: t.albumArtUrl, durationMS: t.durationMs))
        }
        return rows
    }

    /// Fetch playlist contents with bounded concurrency while retaining the
    /// snapshot's playlist order in the exported document. Any failed read fails
    /// the whole export.
    private static func fetchPlaylistRows(
        _ playlists: [SnapshotPlaylistDTO],
        maxConcurrent: Int
    ) async throws -> [(Int, String, [SnapshotTrackDTO])] {
        try await withThrowingTaskGroup(of: (Int, String, [SnapshotTrackDTO]).self) { group in
            var results: [(Int, String, [SnapshotTrackDTO])] = []
            var next = 0

            func enqueue(_ index: Int) {
                let playlist = playlists[index]
                let label = playlist.name?.isEmpty == false
                    ? playlist.name!
                    : "Untitled playlist"
                group.addTask {
                    let tracks = try await BackendAPI.shared.requireSnapshotTracks(
                        snapshotPlaylistID: playlist.id
                    )
                    return (index, label, tracks)
                }
            }

            while next < min(maxConcurrent, playlists.count) {
                enqueue(next)
                next += 1
            }
            for try await result in group {
                results.append(result)
                if next < playlists.count {
                    enqueue(next)
                    next += 1
                }
            }
            return results
        }
    }

    static func csv(from rows: [Row], createdAt: String? = nil) -> String {
        var lines = ["playlist,name,artist,album,uri,album_art_url,playlist_image_url,duration_ms,snapshot_created_at"]
        for r in rows {
            lines.append([
                escape(r.playlist),
                escape(r.name),
                escape(r.artist),
                escape(r.album),
                escape(r.uri),
                escape(r.albumArtURL),
                escape(r.playlistImageURL),
                r.durationMS.map(String.init) ?? "",
                escape(createdAt),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        // Quote if the field contains a comma, quote, or any newline (CR or LF),
        // doubling embedded quotes per RFC 4180.
        if value.contains("\"") || value.contains(",")
            || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
