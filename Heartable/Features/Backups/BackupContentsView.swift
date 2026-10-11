import SwiftUI

/// A concrete collection inside a backup. Keeping this value small lets the
/// parent page navigate immediately; the track payload is fetched only when the
/// user asks to inspect it.
enum BackupContentSelection: Hashable, Identifiable {
    case playlist(id: UUID, name: String?, imageURL: String?, count: Int)
    case likedSongs(snapshotID: UUID, snapshotName: String?, count: Int)

    var id: String {
        switch self {
        case .playlist(let id, _, _, _): "playlist-\(id.uuidString)"
        case .likedSongs(let id, _, _): "liked-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .playlist(_, let name, _, _):
            name?.isEmpty == false ? name! : "Untitled playlist"
        case .likedSongs:
            "Liked Songs"
        }
    }

    var backupName: String? {
        guard case .likedSongs(_, let name, _) = self else { return nil }
        return name?.isEmpty == false ? name : nil
    }

    var imageURL: URL? {
        guard case .playlist(_, _, let value, _) = self else { return nil }
        return value.flatMap(URL.init(string:))
    }

    var expectedCount: Int {
        switch self {
        case .playlist(_, _, _, let count), .likedSongs(_, _, let count): count
        }
    }
}

struct BackupTrackPreview: Identifiable {
    let id: String
    let uri: String
    let name: String?
    let artist: String?
    let album: String?
    let artworkURL: URL?
    let durationMS: Int?
    let position: Int?

    init(_ track: SnapshotTrackDTO, fallbackPosition: Int) {
        uri = track.spotifyTrackUri
        name = track.trackName
        artist = track.artistName
        album = track.albumName
        artworkURL = track.albumArtUrl.flatMap(URL.init(string:))
        durationMS = track.durationMs
        position = track.position
        id = "\(track.spotifyTrackUri)-\(track.position ?? fallbackPosition)"
    }

    init(_ track: SnapshotLikedTrackDTO, fallbackPosition: Int) {
        uri = track.spotifyTrackUri
        name = track.trackName
        artist = track.artistName
        album = track.albumName
        artworkURL = track.albumArtUrl.flatMap(URL.init(string:))
        durationMS = track.durationMs
        position = track.position
        id = "\(track.spotifyTrackUri)-\(track.position ?? fallbackPosition)"
    }

    var providerID: ProviderID? {
        ProviderID(rawValue: String(uri.prefix { $0 != ":" }))
    }
}

/// Read-only inspection of one captured playlist (or the liked-song bucket).
/// Backups are deliberately not playable here: this surface represents the
/// immutable saved copy and keeps restore/delete actions on the parent card.
struct BackupContentsView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let selection: BackupContentSelection

    @State private var tracks: [BackupTrackPreview] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 0) {
                    collectionSummary
                        .padding(.bottom, 16)

                    if loading {
                        ProgressView()
                            .tint(theme.palette.rose)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 44)
                    } else if failed {
                        VStack(spacing: 10) {
                            Text("Couldn’t load all saved tracks.")
                                .font(Typography.body(13))
                                .foregroundStyle(theme.palette.textSecondary)
                            Button("Try again") { Task { await loadTracks() } }
                                .font(Typography.semibold(14))
                                .foregroundStyle(theme.palette.rose)
                                .frame(minHeight: 44)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else if tracks.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                trackRow(track, number: index + 1)
                                if index < tracks.count - 1 {
                                    Divider()
                                        .overlay(theme.palette.border)
                                        .padding(.leading, 68)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(
                            theme.palette.card,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                                .stroke(theme.palette.border, lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { MainThreadStallMonitor.note("open backup contents (\(selection.expectedCount) songs)") }
        .task(id: selection.id) { await loadTracks() }
        .refreshable { await loadTracks() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HeartableNavigationButton(kind: .back, action: dismiss.callAsFunction)
            Text(selection.title)
                .font(Typography.heading(23))
                .foregroundStyle(theme.palette.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background(theme.palette.bg)
    }

    private var collectionSummary: some View {
        HStack(spacing: 14) {
            if let imageURL = selection.imageURL ?? tracks.compactMap(\.artworkURL).first {
                CoverArt(
                    url: imageURL,
                    size: 68,
                    corner: Theme.Radius.md,
                    placeholder: "music.note.list"
                )
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(theme.palette.roseDim)
                    .frame(width: 68, height: 68)
                    .overlay {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(theme.palette.rose)
                    }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(selection.title)
                    .font(Typography.semibold(17))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(2)

                if let backupName = selection.backupName {
                    Text(backupName)
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                }

                Text(trackCountLabel)
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textMuted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trackCountLabel: String {
        let count = loading ? selection.expectedCount : tracks.count
        return "\(count) \(count == 1 ? "track" : "tracks")"
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .medium))
            Text("No tracks were captured here.")
                .font(Typography.body(13))
        }
        .foregroundStyle(theme.palette.textMuted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func trackRow(_ track: BackupTrackPreview, number: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(Typography.body(11))
                .foregroundStyle(theme.palette.textMuted)
                .frame(width: 18, alignment: .trailing)

            CoverArt(url: track.artworkURL, size: 42, corner: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name?.isEmpty == false ? track.name! : "Saved track")
                    .font(Typography.medium(13))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)

                Text(trackDetail(track))
                    .font(Typography.body(11))
                    .foregroundStyle(theme.palette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let providerID = track.providerID {
                ProviderBadge(id: providerID, size: 18)
            }

            if let duration = durationLabel(track.durationMS) {
                Text(duration)
                    .font(Typography.body(10))
                    .monospacedDigit()
                    .foregroundStyle(theme.palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .accessibilityElement(children: .combine)
    }

    private func trackDetail(_ track: BackupTrackPreview) -> String {
        [track.artist, track.album]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    private func durationLabel(_ milliseconds: Int?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        let seconds = milliseconds / 1_000
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func loadTracks() async {
        loading = true
        failed = false
        defer { loading = false }

        do {
            let loaded: [BackupTrackPreview]
            switch selection {
            case .playlist(let id, _, _, _):
                loaded = try await BackendAPI.shared.requireSnapshotTracks(snapshotPlaylistID: id)
                    .enumerated().map { BackupTrackPreview($0.element, fallbackPosition: $0.offset) }
            case .likedSongs(let snapshotID, _, _):
                loaded = try await BackendAPI.shared.requireSnapshotLikedTracks(snapshotID: snapshotID)
                    .enumerated().map { BackupTrackPreview($0.element, fallbackPosition: $0.offset) }
            }
            guard loaded.count == selection.expectedCount else { failed = true; return }
            tracks = loaded
        } catch {
            failed = true
        }
    }
}
