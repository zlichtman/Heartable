import SwiftUI

/// Circular artist image with a person-glyph fallback over the theme surface.
/// Shows the real Spotify artist photo when one was fetched, otherwise the
/// artist's top album art, otherwise the glyph. Used by the Library Artists list
/// and the artist detail header.
struct ArtistAvatar: View {
    @Environment(ThemeStore.self) private var theme
    let url: URL?
    var size: CGFloat = 44

    var body: some View {
        CachedArtworkImage(url: url) {
            ZStack {
                Circle().fill(theme.palette.surface)
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(theme.palette.textMuted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
