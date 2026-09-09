import Foundation
import WidgetKit

/// App-only adapters from rich authenticated models into the secret-free shared
/// widget contract. The WidgetKit extension compiles only the shared snapshot
/// types and never links backend/provider code.
extension WidgetSnapshotStore {
    @MainActor
    static func publish(theme: ThemeDef) {
        if WidgetThemeStore.save(HeartableWidgetTheme(theme: theme)) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @MainActor
    static func update(weeklyRecap recap: WeeklyRecap?) {
        let snapshot = recap.map {
            WidgetWeeklyRecapSnapshot(
                weekStart: $0.weekStart,
                weekEnd: $0.weekEnd,
                playCount: $0.playCount,
                estimatedListeningMilliseconds:
                    $0.estimatedListeningMilliseconds,
                topTrackTitle: $0.topTracks.first?.title,
                topTrackArtist: $0.topTracks.first?.artist,
                topArtistName: $0.topArtists.first?.name
            )
        }
        update(weeklyRecap: snapshot, generatedAt: Date())
        WidgetCenter.shared.reloadTimelines(ofKind: recapWidgetKind)
    }

    /// Integration call for the app-wide FriendActivityRepository:
    /// `WidgetSnapshotStore.update(friendActivity: activity.cached())`.
    @MainActor
    static func update(friendActivity entries: [FriendActivityEntryDTO]) {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        let snapshots: [WidgetFriendActivitySnapshot] = entries.prefix(3)
            .compactMap { entry -> WidgetFriendActivitySnapshot? in
            guard let playedAt =
                fractional.date(from: entry.playedAt)
                ?? standard.date(from: entry.playedAt) else {
                return nil
            }
            return WidgetFriendActivitySnapshot(
                id: entry.activityId,
                friendName: entry.displayName ?? entry.handle ?? "Friend",
                trackTitle: entry.trackName,
                artist: entry.artist,
                playedAt: playedAt
            )
        }
        update(friendActivity: snapshots, generatedAt: Date())
        WidgetCenter.shared.reloadTimelines(ofKind: friendActivityWidgetKind)
    }

    @MainActor
    static func clearAndReloadWidgets() {
        clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension HeartableWidgetTheme {
    /// Resolve the very same semantic palette used by the app, including custom
    /// edits. This is intentionally app-only; widgets never load ThemeStore.
    @MainActor
    init(theme: ThemeDef) {
        let palette = theme.palette
        self.init(
            version: 1, key: theme.key,
            background: RGBAColor(palette.bg), surface: RGBAColor(palette.surface),
            text: RGBAColor(palette.text), secondaryText: RGBAColor(palette.textSecondary),
            accent: RGBAColor(palette.rose), border: RGBAColor(palette.border)
        )
    }
}
