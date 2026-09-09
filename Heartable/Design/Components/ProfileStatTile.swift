import SwiftUI

/// A compact, accent-tinted stat tile (a big value over a quiet caption) used in
/// a row on a profile to surface leaderboard standing, tracks, and minutes. Each
/// tile carries its own accent so a row of them reads as distinct chips rather
/// than one uniform slab.
struct ProfileStatTile: View {
    @Environment(ThemeStore.self) private var theme

    let value: String
    let caption: String
    /// Accent for the value + tint; defaults to the brand rose.
    var accent: Color? = nil
    var systemImage: String? = nil

    private var tint: Color { accent ?? theme.palette.rose }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(value)
                    .font(Typography.heading(20))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(caption.uppercased())
                .font(Typography.semibold(9))
                .tracking(1)
                .foregroundStyle(theme.palette.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }
}
