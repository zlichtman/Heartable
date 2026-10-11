import SwiftUI

/// One bounded two-line capsule in both orientations. Full lyrics are an
/// explicit expansion, never an embedded scroller that grows the player page.
struct LyricsCard: View {
    @Environment(ThemeStore.self) private var theme
    let model: LyricsModel
    let positionMs: Int
    var height: CGFloat = 64
    let onExpand: () -> Void

    private var lines: [String] {
        if model.loading { return ["Finding lyrics…"] }
        let preview = model.previewLines(positionMs: positionMs)
        return preview.isEmpty ? ["Lyrics aren’t available for this track."] : preview
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(index == 0 ? Typography.semibold(14) : Typography.medium(14))
                        .foregroundStyle(index == 0 ? theme.palette.text : theme.palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Lyrics")
            .accessibilityValue(lines.joined(separator: ", "))

            if !model.synced.isEmpty || model.plain != nil {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.palette.text)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand lyrics")
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(theme.palette.card, in: Capsule())
        .overlay(Capsule().stroke(theme.palette.border, lineWidth: 1))
        .accessibilityIdentifier("player.lyricsCard")
    }
}
