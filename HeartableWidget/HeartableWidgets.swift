import SwiftUI
import WidgetKit
import UIKit

private struct HeartableTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: HeartableWidgetSnapshot?
}

private struct HeartableTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeartableTimelineEntry {
        previewEntry()
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (HeartableTimelineEntry) -> Void
    ) {
        if context.isPreview {
            completion(previewEntry())
            return
        }
        completion(
            HeartableTimelineEntry(
                date: Date(),
                snapshot: WidgetSnapshotStore.load()?.displayed(at: Date())
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<HeartableTimelineEntry>) -> Void
    ) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.load()
        let entry = HeartableTimelineEntry(
            date: now,
            snapshot: snapshot?.displayed(at: now)
        )
        // App refreshes explicitly after real data changes. The periodic policy
        // keeps relative timestamps current without network work in the extension.
        var refresh = Calendar.current.date(byAdding: .minute, value: 30, to: now)
            ?? now.addingTimeInterval(30 * 60)
        if let weekEnd = snapshot?.weeklyRecap?.weekEnd, weekEnd > now {
            refresh = min(refresh, weekEnd)
        }
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    /// Gallery-only examples. Never persisted or shown as a real user's stats.
    private func previewEntry() -> HeartableTimelineEntry {
        let now = Date()
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: now)!
        return HeartableTimelineEntry(date: now, snapshot: HeartableWidgetSnapshot(
            version: HeartableWidgetSnapshot.currentVersion,
            generatedAt: now,
            weeklyRecap: WidgetWeeklyRecapSnapshot(
                weekStart: week.start, weekEnd: week.end, playCount: 128,
                estimatedListeningMilliseconds: 25_200_000,
                topTrackTitle: "Space Song", topTrackArtist: "Beach House",
                topArtistName: "Beach House"
            ),
            friendActivity: [
                WidgetFriendActivitySnapshot(id: UUID(), friendName: "Alex",
                    trackTitle: "Pink + White", artist: "Frank Ocean",
                    playedAt: now.addingTimeInterval(-240)),
                WidgetFriendActivitySnapshot(id: UUID(), friendName: "Sam",
                    trackTitle: "Dreams", artist: "Fleetwood Mac",
                    playedAt: now.addingTimeInterval(-720))
            ]
        ))
    }
}

struct WeeklyRecapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSnapshotStore.recapWidgetKind,
            provider: HeartableTimelineProvider()
        ) { entry in
            WeeklyRecapWidgetView(entry: entry)
                .widgetURL(HeartableWidgetRoute.recap.url)
                .privacySensitive()
                .containerBackground(for: .widget) {
                    HeartableWidgetPalette.paper
                }
        }
        .configurationDisplayName("Weekly Recap")
        .description("Your real Heartable plays and estimated listening time this week.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct WeeklyRecapWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeartableTimelineEntry

    var body: some View {
        if let recap = entry.snapshot?.weeklyRecap, recap.playCount > 0 {
            switch family {
            case .systemMedium:
                medium(recap)
            case .accessoryRectangular:
                accessory(recap)
            default:
                small(recap)
            }
        } else if family == .accessoryRectangular {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                Text("Your week starts with a song")
                    .font(.headline)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
        } else {
            emptyRecap
        }
    }

    private func small(_ recap: WidgetWeeklyRecapSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            brandHeader("This week")
            Spacer(minLength: 0)
            Text("\(recap.playCount)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(HeartableWidgetPalette.cocoa)
                .minimumScaleFactor(0.75)
            Text(recap.playCount == 1 ? "play" : "plays")
                .font(.caption)
                .foregroundStyle(HeartableWidgetPalette.cocoaSecondary)
            if let title = recap.topTrackTitle {
                Divider().overlay(HeartableWidgetPalette.brown.opacity(0.18))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HeartableWidgetPalette.cocoa)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recapAccessibility(recap))
    }

    private func medium(_ recap: WidgetWeeklyRecapSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            brandHeader("Your week")
            HStack(spacing: 10) {
                metric("\(recap.playCount)", "plays")
                metric(
                    WeeklyRecapWidgetFormatting.compactDuration(
                        recap.estimatedListeningMilliseconds
                    ),
                    "estimated"
                )
                if let artist = recap.topArtistName {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(artist)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(HeartableWidgetPalette.cocoa)
                            .lineLimit(2)
                        Text("top artist")
                            .font(.caption2)
                            .foregroundStyle(
                                HeartableWidgetPalette.cocoaSecondary
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let title = recap.topTrackTitle {
                HStack(spacing: 7) {
                    Image(systemName: "music.note")
                        .foregroundStyle(HeartableWidgetPalette.pink)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HeartableWidgetPalette.cocoa)
                        .lineLimit(1)
                    if let artist = recap.topTrackArtist {
                        Text("· \(artist)")
                            .font(.caption)
                            .foregroundStyle(
                                HeartableWidgetPalette.cocoaSecondary
                            )
                            .lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recapAccessibility(recap))
    }

    private func accessory(_ recap: WidgetWeeklyRecapSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text("\(recap.playCount) plays this week")
                    .font(.headline)
                    .lineLimit(1)
                Text(
                    WeeklyRecapWidgetFormatting.compactDuration(
                        recap.estimatedListeningMilliseconds
                    ) + " estimated"
                )
                .font(.caption)
                .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recapAccessibility(recap))
    }

    private var emptyRecap: some View {
        VStack(alignment: .leading, spacing: 9) {
            brandHeader("This week")
            Spacer(minLength: 0)
            Image(systemName: "music.note")
                .font(.title2.weight(.semibold))
                .foregroundStyle(HeartableWidgetPalette.pink)
            Text("Your week starts with a song.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HeartableWidgetPalette.cocoa)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func brandHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .foregroundStyle(HeartableWidgetPalette.pink)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(HeartableWidgetPalette.cocoaSecondary)
                .lineLimit(1)
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(HeartableWidgetPalette.cocoa)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2)
                .foregroundStyle(HeartableWidgetPalette.cocoaSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recapAccessibility(_ recap: WidgetWeeklyRecapSnapshot) -> String {
        var value =
            "\(recap.playCount) qualified plays this week, "
            + WeeklyRecapWidgetFormatting.compactDuration(
                recap.estimatedListeningMilliseconds
            )
            + " estimated listening time"
        if let track = recap.topTrackTitle {
            value += ", top track \(track)"
        }
        return value
    }
}

struct FriendActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSnapshotStore.friendActivityWidgetKind,
            provider: HeartableTimelineProvider()
        ) { entry in
            FriendActivityWidgetView(entry: entry)
                .widgetURL(HeartableWidgetRoute.friends.url)
                .containerBackground(for: .widget) {
                    HeartableWidgetPalette.paper
                }
                .privacySensitive()
        }
        .configurationDisplayName("Friends Listening")
        .description("Recent qualified plays from your Heartable friends.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct FriendActivityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeartableTimelineEntry

    private var activity: [WidgetFriendActivitySnapshot] {
        entry.snapshot?.friendActivity ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(HeartableWidgetPalette.pink)
                Text("Friends listening")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HeartableWidgetPalette.cocoaSecondary)
                    .lineLimit(1)
            }

            if activity.isEmpty {
                Spacer(minLength: 0)
                Text("No recent friend plays.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeartableWidgetPalette.cocoa)
                    .lineLimit(3)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(activity.prefix(family == .systemMedium ? 2 : 1))) {
                        item in
                        activityRow(item)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func activityRow(_ item: WidgetFriendActivitySnapshot) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "heart.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(HeartableWidgetPalette.paper)
                .frame(width: 30, height: 30)
                .background(HeartableWidgetPalette.brown, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.friendName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HeartableWidgetPalette.cocoaSecondary)
                    .lineLimit(1)
                Text(item.trackTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeartableWidgetPalette.cocoa)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let artist = item.artist, !artist.isEmpty {
                        Text(artist)
                            .lineLimit(1)
                    }
                    Text(item.playedAt, style: .relative)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(HeartableWidgetPalette.cocoaSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private enum HeartableWidgetPalette {
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.09, blue: 0.09, alpha: 1)
            : UIColor(red: 1, green: 244.0 / 255, blue: 239.0 / 255, alpha: 1)
    })
    static let cocoa = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.98, green: 0.91, blue: 0.87, alpha: 1)
            : UIColor(red: 67.0 / 255, green: 43.0 / 255, blue: 43.0 / 255, alpha: 1)
    })
    static let cocoaSecondary = cocoa.opacity(0.70)
    static let brown = Color(red: 140 / 255, green: 90 / 255, blue: 80 / 255)
    static let pink = Color(red: 232 / 255, green: 69 / 255, blue: 124 / 255)
}

struct QuickAccessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSnapshotStore.quickAccessWidgetKind,
            provider: HeartableTimelineProvider()
        ) { _ in
            QuickAccessWidgetView()
                .containerBackground(HeartableWidgetPalette.paper, for: .widget)
        }
        .configurationDisplayName("Heartable Shortcuts")
        .description("Open your library, friends, or playlist backups.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

private struct QuickAccessWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            Image(systemName: "heart.fill")
                .widgetAccentable()
                .widgetURL(HeartableWidgetRoute.library.url)
                .accessibilityLabel("Open Heartable library")
        } else if family == .systemSmall {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(HeartableWidgetPalette.pink)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text("Heartable")
                    .font(.system(.title3, design: .serif, weight: .bold))
                HStack {
                    Text("Your library").font(.caption)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(HeartableWidgetPalette.cocoa)
            .widgetURL(HeartableWidgetRoute.library.url)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open Heartable library")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(HeartableWidgetPalette.pink)
                    Text("Heartable")
                        .font(.system(.headline, design: .serif))
                }
                HStack(spacing: 12) {
                    shortcut(.library, "Library", "music.note.house.fill")
                    shortcut(.friends, "Friends", "person.2.fill")
                    shortcut(.backups, "Backups", "externaldrive.fill")
                }
            }
            .foregroundStyle(HeartableWidgetPalette.cocoa)
        }
    }

    private func shortcut(_ route: HeartableWidgetRoute, _ title: String, _ icon: String) -> some View {
        Link(destination: route.url) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(HeartableWidgetPalette.pink)
                    .widgetAccentable()
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(HeartableWidgetPalette.brown.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityLabel("Open \(title)")
    }
}

private enum WeeklyRecapWidgetFormatting {
    static func compactDuration(_ milliseconds: Int64) -> String {
        let totalMinutes = max(0, milliseconds) / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}
