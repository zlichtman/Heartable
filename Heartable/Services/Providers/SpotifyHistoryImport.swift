import Foundation
import Supabase

struct SpotifyRecentHistory: Decodable, Sendable {
    let items: [SpotifyRecentPlay]?
}

struct SpotifyRecentPlay: Decodable, Sendable {
    let track: SpotifyTrack
    let playedAt: String
    enum CodingKeys: String, CodingKey { case track; case playedAt = "played_at" }

    var payload: SpotifyHistoryPayload? {
        guard track.uri.hasPrefix("spotify:track:"), !track.id.isEmpty,
              HistoryTimestamp.date(playedAt) != nil else { return nil }
        return .init(trackUri: track.uri, trackName: track.name,
                     artist: (track.artists ?? []).compactMap(\.name).joined(separator: ", "),
                     durationMs: max(0, track.durationMs ?? 0), playedAt: playedAt,
                     albumArt: track.album?.images?.first?.url)
    }
}

struct SpotifyHistoryPayload: Codable, Sendable {
    let trackUri: String
    let trackName: String
    let artist: String
    let durationMs: Int
    let playedAt: String
    let albumArt: String?
    enum CodingKeys: String, CodingKey {
        case artist
        case trackUri = "track_uri", trackName = "track_name", durationMs = "duration_ms"
        case playedAt = "played_at", albumArt = "album_art"
    }
}

enum HistoryTimestamp {
    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct ListeningHistoryItem: Identifiable, Sendable {
    let entry: PlayEntryDTO
    let imported: Bool
    var id: UUID { entry.id }

    static func merge(observed: [PlayEntryDTO], imported: [PlayEntryDTO]) -> [Self] {
        // Onboarding normally precedes observed plays. On an existing account,
        // hide an imported copy of a play already captured around that timestamp.
        let uniqueImports = imported.filter { candidate in
            guard let time = candidate.playedAt.flatMap(HistoryTimestamp.date) else { return false }
            return !observed.contains { logged in
                guard logged.trackUri == candidate.trackUri,
                      let loggedTime = logged.playedAt.flatMap(HistoryTimestamp.date) else { return false }
                return abs(time.timeIntervalSince(loggedTime)) <= 60
            }
        }
        return (observed.map { Self(entry: $0, imported: false) }
                + uniqueImports.map { Self(entry: $0, imported: true) })
            .sorted {
                let lhs = $0.entry.playedAt.flatMap(HistoryTimestamp.date) ?? .distantPast
                let rhs = $1.entry.playedAt.flatMap(HistoryTimestamp.date) ?? .distantPast
                return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs > rhs
            }
    }
}

/// Best-effort, one-time onboarding import. Its durable marker is committed in
/// the same transaction as the rows. Account changes cancel this work; transient
/// failures leave the marker unset and can retry on a later activation/reconnect.
enum SpotifyHistoryImport {
    @MainActor
    static func run(ownerID: UUID) async {
        do {
            guard AccountSessionStore.currentOwnerID == ownerID,
                  try await BackendAPI.shared.needsSpotifyHistoryImport(userID: ownerID) else { return }
            try Task.checkCancellation()
            guard let token = await SpotifyAuth.getValidAccessToken(),
                  AccountSessionStore.currentOwnerID == ownerID else { return }
            let plays = try await SpotifyAPI.recentlyPlayed(token: token)
            try Task.checkCancellation()
            guard AccountSessionStore.currentOwnerID == ownerID else { return }
            try await BackendAPI.shared.importSpotifyHistory(
                plays.compactMap(\.payload), userID: ownerID
            )
            guard AccountSessionStore.currentOwnerID == ownerID, !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .heartableHistoryImported, object: ownerID)
        } catch {
            // No partial import and no fabricated play counts. Older Spotify
            // grants acquire user-read-recently-played on the next reconnect.
        }
    }
}

extension BackendAPI {
    func needsSpotifyHistoryImport(userID: UUID) async throws -> Bool {
        struct Marker: Decodable {
            let importedAt: String?
            enum CodingKeys: String, CodingKey { case importedAt = "spotify_history_imported_at" }
        }
        let client = SupabaseClientProvider.shared
        guard try await client.auth.session.user.id == userID else { throw BackendError.notSignedIn }
        let rows: [Marker] = try await client.from("profiles")
            .select("spotify_history_imported_at").eq("user_id", value: userID.uuidString)
            .limit(1).execute().value
        return rows.first.map { $0.importedAt == nil } ?? false
    }

    func importSpotifyHistory(_ plays: [SpotifyHistoryPayload], userID: UUID) async throws {
        struct Params: Encodable {
            let expected_owner: UUID
            let plays: [SpotifyHistoryPayload]
        }
        let client = SupabaseClientProvider.shared
        guard try await client.auth.session.user.id == userID else { throw BackendError.notSignedIn }
        try await client.rpc("import_spotify_history", params: Params(expected_owner: userID, plays: Array(plays.prefix(50))))
            .execute()
    }

    func fetchListeningHistory(limit: Int = 200) async -> [ListeningHistoryItem] {
        let client = SupabaseClientProvider.shared
        guard let owner = try? await client.auth.session.user.id else { return [] }
        async let observed = fetchPlayHistory(limit: limit, userID: owner)
        let imported: [PlayEntryDTO] = (try? await client.from("provider_play_history")
            .select("id,track_uri,track_name,artist,duration_ms,played_at,album_art")
            .eq("user_id", value: owner.uuidString).order("played_at", ascending: false)
            .limit(limit).execute().value) ?? []
        let recorded = await observed
        guard (try? await client.auth.session.user.id) == owner else { return [] }
        return ListeningHistoryItem.merge(observed: recorded, imported: imported)
    }

    func deleteImportedPlay(id: UUID) async throws {
        try await SupabaseClientProvider.shared.from("provider_play_history")
            .delete().eq("id", value: id.uuidString).execute()
    }
}
