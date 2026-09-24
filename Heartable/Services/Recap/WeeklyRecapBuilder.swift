import Foundation

/// Pure weekly aggregation kept separate from networking and persistence so its
/// date boundaries, cross-service de-duplication, and ranking are deterministic.
enum WeeklyRecapBuilder {
    private struct ParsedPlay {
        let entry: PlayEntryDTO
        let playedAt: Date
        let title: String
        let artist: String
        let durationMs: Int64
    }

    private struct TrackAccumulator {
        var title: String
        var artist: String
        var albumArtURL: String?
        var playCount: Int
        var durationMs: Int64
        var lastPlayedAt: Date
    }

    private struct ArtistAccumulator {
        var name: String
        var playCount: Int
        var durationMs: Int64
        var lastPlayedAt: Date
    }

    static func makeCollection(
        entries: [PlayEntryDTO],
        now: Date = Date(),
        calendar: Calendar = recapCalendar()
    ) -> WeeklyRecapCollection {
        let parsed = parse(entries)
        let currentInterval = weekInterval(containing: now, calendar: calendar)
        let current = build(
            parsed: parsed,
            interval: currentInterval,
            generatedAt: now
        )

        guard let earliest = parsed.map(\.playedAt).min() else {
            return WeeklyRecapCollection(current: current, completed: [])
        }

        var completed: [WeeklyRecap] = []
        var cursor = weekInterval(containing: earliest, calendar: calendar).start
        while cursor < currentInterval.start {
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor)
            else { break }
            let recap = build(
                parsed: parsed,
                interval: DateInterval(start: cursor, end: next),
                generatedAt: now
            )
            if !recap.isEmpty { completed.append(recap) }
            cursor = next
        }

        return WeeklyRecapCollection(
            current: current,
            completed: completed.sorted { $0.weekStart > $1.weekStart }
        )
    }

    static func make(
        entries: [PlayEntryDTO],
        interval: DateInterval,
        generatedAt: Date = Date()
    ) -> WeeklyRecap {
        build(
            parsed: parse(entries),
            interval: interval,
            generatedAt: generatedAt
        )
    }

    static func recapCalendar(timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar
    }

    static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
            return interval
        }
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start)
            ?? start.addingTimeInterval(7 * 86_400)
        return DateInterval(start: start, end: end)
    }

    private static func build(
        parsed: [ParsedPlay],
        interval: DateInterval,
        generatedAt: Date
    ) -> WeeklyRecap {
        var tracks: [String: TrackAccumulator] = [:]
        var artists: [String: ArtistAccumulator] = [:]
        var playCount = 0
        var totalDurationMs: Int64 = 0

        for play in parsed where
            play.playedAt >= interval.start && play.playedAt < interval.end
        {
            playCount += 1
            totalDurationMs += play.durationMs

            let identity = UnifiedTrackIdentity.make(
                title: play.title,
                artist: play.artist
            )
            if var track = tracks[identity.key] {
                track.playCount += 1
                track.durationMs += play.durationMs
                if play.playedAt > track.lastPlayedAt {
                    track.lastPlayedAt = play.playedAt
                    track.title = play.title
                    track.artist = play.artist
                }
                if track.albumArtURL == nil {
                    track.albumArtURL = play.entry.albumArt
                }
                tracks[identity.key] = track
            } else {
                tracks[identity.key] = TrackAccumulator(
                    title: play.title,
                    artist: play.artist,
                    albumArtURL: play.entry.albumArt,
                    playCount: 1,
                    durationMs: play.durationMs,
                    lastPlayedAt: play.playedAt
                )
            }

            let artistID = UnifiedTrackIdentity.normalizeArtist(play.artist)
            guard !artistID.isEmpty else { continue }
            if var artist = artists[artistID] {
                artist.playCount += 1
                artist.durationMs += play.durationMs
                if play.playedAt > artist.lastPlayedAt {
                    artist.lastPlayedAt = play.playedAt
                    artist.name = play.artist
                }
                artists[artistID] = artist
            } else {
                artists[artistID] = ArtistAccumulator(
                    name: play.artist,
                    playCount: 1,
                    durationMs: play.durationMs,
                    lastPlayedAt: play.playedAt
                )
            }
        }

        let rankedTracks = tracks.map { key, value in
            WeeklyRecapTrack(
                id: key,
                title: value.title,
                artist: value.artist.isEmpty ? "Unknown artist" : value.artist,
                albumArtURL: value.albumArtURL,
                playCount: value.playCount,
                estimatedListeningMilliseconds: value.durationMs,
                lastPlayedAt: value.lastPlayedAt
            )
        }
        .sorted(by: trackRanksBefore)

        let rankedArtists = artists.map { key, value in
            WeeklyRecapArtist(
                id: key,
                name: value.name,
                playCount: value.playCount,
                estimatedListeningMilliseconds: value.durationMs,
                lastPlayedAt: value.lastPlayedAt
            )
        }
        .sorted(by: artistRanksBefore)

        return WeeklyRecap(
            weekStart: interval.start,
            weekEnd: interval.end,
            generatedAt: generatedAt,
            playCount: playCount,
            estimatedListeningMilliseconds: totalDurationMs,
            uniqueTrackCount: tracks.count,
            uniqueArtistCount: artists.count,
            topTracks: Array(rankedTracks.prefix(10)),
            topArtists: Array(rankedArtists.prefix(10))
        )
    }

    private static func parse(_ entries: [PlayEntryDTO]) -> [ParsedPlay] {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()

        return entries.compactMap { entry in
            guard let playedAtString = entry.playedAt,
                  let playedAt =
                    fractional.date(from: playedAtString)
                    ?? standard.date(from: playedAtString),
                  let title = entry.trackName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return nil
            }
            let artist = entry.artist?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ParsedPlay(
                entry: entry,
                playedAt: playedAt,
                title: title,
                artist: artist,
                durationMs: Int64(max(0, entry.durationMs ?? 0))
            )
        }
    }

    private static func trackRanksBefore(
        _ lhs: WeeklyRecapTrack,
        _ rhs: WeeklyRecapTrack
    ) -> Bool {
        if lhs.playCount != rhs.playCount { return lhs.playCount > rhs.playCount }
        if lhs.lastPlayedAt != rhs.lastPlayedAt {
            return lhs.lastPlayedAt > rhs.lastPlayedAt
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func artistRanksBefore(
        _ lhs: WeeklyRecapArtist,
        _ rhs: WeeklyRecapArtist
    ) -> Bool {
        if lhs.playCount != rhs.playCount { return lhs.playCount > rhs.playCount }
        if lhs.lastPlayedAt != rhs.lastPlayedAt {
            return lhs.lastPlayedAt > rhs.lastPlayedAt
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
