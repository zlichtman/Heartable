import SwiftUI

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
