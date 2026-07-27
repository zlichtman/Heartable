import Foundation

/// One honest weekly summary built exclusively from Heartable's qualified
/// `play_log` events. Listening time is explicitly estimated because each row
/// stores the track's duration, not a second-by-second playback ledger.
struct WeeklyRecap: Codable, Sendable, Equatable, Identifiable {
    let weekStart: Date
    let weekEnd: Date
    let generatedAt: Date
    let playCount: Int
    let estimatedListeningMilliseconds: Int64
    let uniqueTrackCount: Int
    let uniqueArtistCount: Int
    let topTracks: [WeeklyRecapTrack]
    let topArtists: [WeeklyRecapArtist]

    var id: String {
        String(Int(weekStart.timeIntervalSince1970))
    }

    var isEmpty: Bool { playCount == 0 }

    var shareText: String {
        var lines = [
            "My Heartable week: \(playCount) \(playCount == 1 ? "play" : "plays")",
            "\(Self.compactDuration(estimatedListeningMilliseconds)) estimated listening time",
        ]
        if let track = topTracks.first {
            lines.append("Top track: \(track.title) — \(track.artist)")
        }
        if let artist = topArtists.first {
            lines.append("Top artist: \(artist.name)")
        }
        return lines.joined(separator: "\n")
    }

    static func compactDuration(_ milliseconds: Int64) -> String {
        let totalMinutes = max(0, milliseconds) / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}

struct WeeklyRecapTrack: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let albumArtURL: String?
    let playCount: Int
    let estimatedListeningMilliseconds: Int64
    let lastPlayedAt: Date
}

struct WeeklyRecapArtist: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let playCount: Int
    let estimatedListeningMilliseconds: Int64
    let lastPlayedAt: Date
}

struct WeeklyRecapCollection: Sendable, Equatable {
    let current: WeeklyRecap
    let completed: [WeeklyRecap]
}
