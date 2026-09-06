import SwiftUI

/// Lyrics are visible in the player, not hidden behind a navigation pill.
/// Only the expansion affordance is a button; plain lyrics remain scrollable.
struct LyricsCard: View {
    @Environment(ThemeStore.self) private var theme
    let model: LyricsModel
    let positionMs: Int
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lyrics").font(Typography.semibold(14))
                Spacer()
                if !model.synced.isEmpty || model.plain != nil {
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Expand lyrics")
                }
            }
            .foregroundStyle(theme.palette.text)
            .frame(height: 32)

            Group {
                if model.loading {
                    Text("Finding lyrics…").foregroundStyle(theme.palette.textMuted)
                } else if !model.synced.isEmpty {
                    let active = model.currentIndex(positionMs: positionMs)
                    let indices = LyricsModel.previewIndices(active: active, count: model.synced.count)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(indices, id: \.self) { index in
                            Text(model.synced[index].text)
                                .font(index == active ? Typography.semibold(20) : Typography.medium(17))
                                .foregroundStyle(index == active ? theme.palette.rose : theme.palette.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let plain = model.plain {
                    ScrollView {
                        Text(plain).font(Typography.medium(18))
                            .foregroundStyle(theme.palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    Text("Lyrics aren’t available for this track.")
                        .foregroundStyle(theme.palette.textMuted)
                }
            }
            .font(Typography.body(14))
            .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 150, alignment: .topLeading)
        }
        .padding(18)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.palette.border, lineWidth: 1))
        .accessibilityIdentifier("player.lyricsCard")
    }
}
