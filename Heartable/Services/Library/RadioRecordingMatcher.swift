import Foundation

/// Broadcast logs contain names, not provider recording identifiers. Prefer a
/// missed match to playing another artist, remix or live edition by mistake.
enum RadioRecordingMatcher {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func match(_ spin: WSUMSpin, in candidates: [UnifiedTrack]) -> UnifiedTrack? {
        let title = normalized(spin.song), artist = normalized(spin.artist), album = normalized(spin.album)
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return candidates.filter {
            normalized($0.name) == title && normalized($0.artistNames) == artist &&
            (album.isEmpty || normalized($0.album ?? "") == album) && !$0.uri.isEmpty
        }.sorted {
            if $0.providerID != $1.providerID {
                return ArtworkSourcePreference.precedes($0.providerID, $1.providerID)
            }
            if ($0.albumArt != nil) != ($1.albumArt != nil) { return $0.albumArt != nil }
            return $0.key < $1.key
        }.first
    }
}

/// Small, account-scoped session cache. Failed lookups are not persisted: an
/// outage or rate limit must never permanently label a recording unavailable.
@MainActor
final class RadioRecordingCache {
    static let shared = RadioRecordingCache()
    private var owner: UUID?
    private var matches: [String: UnifiedTrack] = [:]

    private func key(_ spin: WSUMSpin) -> String {
        [spin.song, spin.artist, spin.album].map(RadioRecordingMatcher.normalized).joined(separator: "\u{1f}")
    }

    func match(_ spin: WSUMSpin, connected: Set<ProviderID>) -> UnifiedTrack? {
        if owner != AccountSessionStore.currentOwnerID {
            matches.removeAll()
            owner = AccountSessionStore.currentOwnerID
        }
        guard let track = matches[key(spin)], connected.contains(track.providerID) else { return nil }
        return track
    }

    func store(_ track: UnifiedTrack, for spin: WSUMSpin) {
        _ = match(spin, connected: [])
        if matches.count >= 500 { matches.removeAll() }
        matches[key(spin)] = track
    }
}
