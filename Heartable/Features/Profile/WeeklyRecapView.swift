import SwiftUI

/// Current-week listening story followed by a durable, device-local archive of
/// completed weeks. Every number comes from qualified Heartable play history.
struct WeeklyRecapView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(BannerCenter.self) private var banners
    @Environment(WeeklyRecapStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if store.isLoading, store.current == nil, store.archived.isEmpty {
                    loadingState
                } else {
                    currentSection
                    archiveSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle("Weekly Recap")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.refresh()
            showErrorIfNeeded()
        }
        .task {
            await store.load()
            showErrorIfNeeded()
        }
    }

    @ViewBuilder
    private var currentSection: some View {
        if let recap = store.current, !recap.isEmpty {
            RecapStoryCard(recap: recap, eyebrow: "THIS WEEK")

            if !recap.topTracks.isEmpty {
                recapHeading("Top tracks")
                RecapTrackList(tracks: Array(recap.topTracks.prefix(5)))
            }

            if !recap.topArtists.isEmpty {
                recapHeading("Top artists")
                RecapArtistGrid(artists: Array(recap.topArtists.prefix(4)))
            }

            HStack {
                Text("Listening time is estimated from the recorded track lengths.")
                    .font(Typography.body(11))
                    .foregroundStyle(theme.palette.textMuted)
                Spacer(minLength: 8)
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.palette.rose)
                        .accessibilityLabel("Refreshing recap")
                }
            }
        } else {
            emptyCurrentWeek
        }
    }

    @ViewBuilder
    private var archiveSection: some View {
        if !store.archived.isEmpty {
            recapHeading("Past weeks")
                .padding(.top, 4)

            LazyVStack(spacing: 10) {
                ForEach(store.archived) { recap in
                    NavigationLink {
                        WeeklyRecapDetailView(recap: recap)
                    } label: {
                        archiveRow(recap)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(theme.palette.rose)
            Text("Building your week")
                .font(Typography.semibold(14))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var emptyCurrentWeek: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(theme.palette.rose)
                .frame(width: 64, height: 64)
                .background(theme.palette.roseDim, in: Circle())
            VStack(spacing: 5) {
                Text("Your week starts with a song")
                    .font(Typography.heading(22))
                    .foregroundStyle(theme.palette.text)
                Text("Qualified plays will shape your recap as you listen.")
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 38)
        .background(
            theme.palette.card,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(theme.palette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func recapHeading(_ title: String) -> some View {
        Text(title)
            .font(Typography.semibold(12))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(theme.palette.textSecondary)
    }

    private func archiveRow(_ recap: WeeklyRecap) -> some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text(recap.weekStart.formatted(.dateTime.month(.abbreviated).day())
                     + " – "
                     + recap.weekEnd.addingTimeInterval(-1)
                        .formatted(.dateTime.month(.abbreviated).day()))
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                Text("\(recap.playCount) plays · \(WeeklyRecap.compactDuration(recap.estimatedListeningMilliseconds))")
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let track = recap.topTracks.first {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(track.title)
                        .font(Typography.medium(12))
                        .foregroundStyle(theme.palette.text)
                        .lineLimit(1)
                    Text("top track")
                        .font(Typography.body(10))
                        .foregroundStyle(theme.palette.textMuted)
                }
                .frame(maxWidth: 110, alignment: .trailing)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.palette.textMuted)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(
            theme.palette.card,
            in: RoundedRectangle(cornerRadius: Theme.Radius.md)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(theme.palette.border, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this weekly recap")
    }

    private func showErrorIfNeeded() {
        if let error = store.errorMessage {
            banners.error(error)
        }
    }
}

private struct WeeklyRecapDetailView: View {
    @Environment(ThemeStore.self) private var theme
    let recap: WeeklyRecap

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                RecapStoryCard(recap: recap, eyebrow: "WEEKLY ARCHIVE")
                if !recap.topTracks.isEmpty {
                    sectionTitle("Top tracks")
                    RecapTrackList(tracks: recap.topTracks)
                }
                if !recap.topArtists.isEmpty {
                    sectionTitle("Top artists")
                    RecapArtistGrid(artists: recap.topArtists)
                }
                Text("Listening time is estimated from the recorded track lengths.")
                    .font(Typography.body(11))
                    .foregroundStyle(theme.palette.textMuted)
            }
            .padding(16)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle(
            recap.weekStart.formatted(.dateTime.month(.wide).day())
        )
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Typography.semibold(12))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(theme.palette.textSecondary)
    }
}

private struct RecapStoryCard: View {
    @Environment(ThemeStore.self) private var theme
    let recap: WeeklyRecap
    let eyebrow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .font(Typography.semibold(10))
                        .tracking(1.2)
                        .foregroundStyle(theme.palette.textSecondary)
                    Text(dateRange)
                        .font(Typography.heading(26))
                        .foregroundStyle(theme.palette.text)
                }
                Spacer(minLength: 8)
                ShareLink(item: recap.shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.palette.rose)
                        .frame(width: 44, height: 44)
                        .background(theme.palette.card.opacity(0.78), in: Circle())
                }
                .accessibilityLabel("Share weekly recap")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    metric("\(recap.playCount)", label: "plays")
                    metric(
                        WeeklyRecap.compactDuration(
                            recap.estimatedListeningMilliseconds
                        ),
                        label: "estimated"
                    )
                    metric("\(recap.uniqueArtistCount)", label: "artists")
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        metric("\(recap.playCount)", label: "plays")
                        metric(
                            WeeklyRecap.compactDuration(
                                recap.estimatedListeningMilliseconds
                            ),
                            label: "estimated"
                        )
                    }
                    metric("\(recap.uniqueArtistCount)", label: "artists")
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.palette.grad1.opacity(0.24),
                            theme.palette.rose.opacity(0.14),
                            theme.palette.bgElevated,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(theme.palette.border, lineWidth: 1)
        }
    }

    private var dateRange: String {
        recap.weekStart.formatted(.dateTime.month(.abbreviated).day())
            + " – "
            + recap.weekEnd.addingTimeInterval(-1)
                .formatted(.dateTime.month(.abbreviated).day())
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Typography.heading(22))
                .foregroundStyle(theme.palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(Typography.body(11))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(.horizontal, 12)
        .background(theme.palette.card.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .accessibilityElement(children: .combine)
    }
}

private struct RecapTrackList: View {
    @Environment(ThemeStore.self) private var theme
    let tracks: [WeeklyRecapTrack]

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        rank(index)
                        trackCopy(track)
                        Spacer(minLength: 6)
                        playCount(track)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            rank(index)
                            trackCopy(track)
                        }
                        playCount(track)
                    }
                }
                .padding(12)
                .background(
                    theme.palette.card,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(theme.palette.border, lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func rank(_ index: Int) -> some View {
        Text("\(index + 1)")
            .font(Typography.heading(17))
            .foregroundStyle(index == 0 ? theme.palette.rose : theme.palette.textMuted)
            .frame(width: 26)
    }

    private func trackCopy(_ track: WeeklyRecapTrack) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title)
                .font(Typography.semibold(14))
                .foregroundStyle(theme.palette.text)
                .lineLimit(2)
            Text(track.artist)
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playCount(_ track: WeeklyRecapTrack) -> some View {
        Text("\(track.playCount) \(track.playCount == 1 ? "play" : "plays")")
            .font(Typography.semibold(11))
            .foregroundStyle(theme.palette.rose)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(theme.palette.roseDim, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct RecapArtistGrid: View {
    @Environment(ThemeStore.self) private var theme
    let artists: [WeeklyRecapArtist]
    private let columns = [
        GridItem(.adaptive(minimum: 142), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(artists) { artist in
                VStack(alignment: .leading, spacing: 5) {
                    Text(artist.name)
                        .font(Typography.semibold(14))
                        .foregroundStyle(theme.palette.text)
                        .lineLimit(2)
                    Text("\(artist.playCount) \(artist.playCount == 1 ? "play" : "plays")")
                        .font(Typography.body(11))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .padding(12)
                .background(
                    theme.palette.card,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(theme.palette.border, lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
