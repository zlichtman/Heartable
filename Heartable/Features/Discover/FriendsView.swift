import SwiftUI

/// Friends — incoming requests (accept/decline) plus a live "now playing" feed.
/// Reached from the Discover tab. Ported from the RN FriendsScreen.
struct FriendsView: View {
    @Environment(ThemeStore.self) private var theme

    @State private var requests: [FriendDTO] = []
    @State private var feed: [FriendNowPlayingDTO] = []

    var body: some View {
        ZStack {
            theme.palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !requests.isEmpty {
                        sectionHeader("Requests")
                        ForEach(requests) { req in requestRow(req) }
                    }

                    sectionHeader("Listening now")
                    if feed.isEmpty {
                        emptyCard
                    } else {
                        ForEach(feed) { f in feedRow(f) }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
        .navigationTitle("Friends")
        .navigationDestination(for: FriendRef.self) { ref in
            FriendProfileView(userId: ref.userId,
                              displayName: ref.displayName,
                              avatarUrl: ref.avatarUrl)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AddFriendView() } label: {
                    Image(systemName: "person.badge.plus")
                }
                .tint(theme.palette.rose)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        async let r = BackendAPI.shared.listIncomingRequests()
        async let f = BackendAPI.shared.getFriendsNowPlaying()
        requests = await r
        feed = await f
    }

    private func respond(_ req: FriendDTO, accept: Bool) async {
        try? await BackendAPI.shared.respondToFriendRequest(id: req.id, accept: accept)
        await load()
    }

    // MARK: Rows

    private func requestRow(_ req: FriendDTO) -> some View {
        HStack(spacing: 10) {
            AvatarCircle(urlString: req.profile?.avatarUrl,
                         name: req.profile?.displayName, size: 42)
            Text(req.profile?.displayName ?? req.profile?.spotifyId ?? "Someone")
                .font(Typography.semibold(14))
                .foregroundStyle(theme.palette.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Accept") { Task { await respond(req, accept: true) } }
                .font(Typography.semibold(12))
                .foregroundStyle(.white)
                .padding(.vertical, 7).padding(.horizontal, 14)
                .background(theme.palette.rose, in: Capsule())
            Button("Decline") { Task { await respond(req, accept: false) } }
                .font(Typography.medium(12))
                .foregroundStyle(theme.palette.textSecondary)
                .padding(.vertical, 7).padding(.horizontal, 12)
                .overlay(Capsule().stroke(theme.palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }

    private func feedRow(_ f: FriendNowPlayingDTO) -> some View {
        NavigationLink(value: FriendRef(userId: f.userId,
                                        displayName: f.displayName,
                                        avatarUrl: f.avatarUrl)) {
            HStack(spacing: 12) {
                AvatarCircle(urlString: f.avatarUrl, name: f.displayName, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.displayName ?? "Friend")
                        .font(Typography.semibold(14))
                        .foregroundStyle(theme.palette.text)
                        .lineLimit(1)
                    Text(trackLine(f))
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                ArtworkThumb(urlString: f.albumArt, size: 38, corner: 8)
                Text(relativeShort(f.updatedAt))
                    .font(Typography.body(11))
                    .foregroundStyle(theme.palette.textMuted)
                    .frame(width: 30, alignment: .trailing)
            }
            .padding(12)
            .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(theme.palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    private func trackLine(_ f: FriendNowPlayingDTO) -> String {
        guard let name = f.trackName else { return "Not listening" }
        let prefix = f.isPlaying ? "▶ " : ""
        if let artist = f.artist, !artist.isEmpty { return "\(prefix)\(name) · \(artist)" }
        return "\(prefix)\(name)"
    }

    // MARK: Atoms

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typography.semibold(12))
            .tracking(1)
            .foregroundStyle(theme.palette.textMuted)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 26))
                .foregroundStyle(theme.palette.textMuted)
            Text("No friends yet. Tap the add button to share your invite or find someone by their username.")
                .font(Typography.body(13))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(theme.palette.border, lineWidth: 1)
        )
    }
}

// MARK: - Shared social atoms

/// A circular avatar from a URL string, falling back to the first letter of the
/// name over the surface color. Used across all Discover/Social screens.
struct AvatarCircle: View {
    @Environment(ThemeStore.self) private var theme
    let urlString: String?
    let name: String?
    var size: CGFloat = 42

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedArtworkImage(url: url) { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        ZStack {
            theme.palette.surface
            Text(String((name ?? "?").prefix(1)).uppercased())
                .font(Typography.semibold(size * 0.38))
                .foregroundStyle(theme.palette.text)
        }
    }
}

/// A small rounded-square artwork thumbnail; renders nothing-but-placeholder when
/// the URL is absent. Used in the friends feed + profile.
struct ArtworkThumb: View {
    @Environment(ThemeStore.self) private var theme
    let urlString: String?
    var size: CGFloat = 48
    var corner: CGFloat = 8

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedArtworkImage(url: url) { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }

    private var placeholder: some View {
        ZStack {
            theme.palette.surface
            Image(systemName: "music.note").foregroundStyle(theme.palette.textMuted)
        }
    }
}

/// ISO8601 → compact relative age ("now"/"5m"/"2h"/"3d"). Degrades to "" on a
/// missing/unparseable timestamp. Shared by the friends feed.
func relativeShort(_ iso: String) -> String {
    guard !iso.isEmpty, let date = parseISO(iso) else { return "" }
    let s = Int(Date().timeIntervalSince(date))
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
}

/// ISO8601 → "Nh ago" style phrasing for profile cards.
func relativeLong(_ iso: String) -> String {
    guard !iso.isEmpty, let date = parseISO(iso) else { return "" }
    let s = Int(Date().timeIntervalSince(date))
    if s < 60 { return "just now" }
    if s < 3600 { return "\(s / 60)m ago" }
    if s < 86400 { return "\(s / 3600)h ago" }
    return "\(s / 86400)d ago"
}

/// Parse an ISO8601 timestamp with or without fractional seconds.
private func parseISO(_ iso: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: iso) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: iso)
}
