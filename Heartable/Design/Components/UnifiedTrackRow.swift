import SwiftUI

/// Standard track row: artwork, title/artist, a provider brand dot, optional
/// rank. Tapping plays it; long-pressing reveals the song's shuffle controls
/// without adding permanent chrome to every row.
struct UnifiedTrackRow: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlaybackPrefsStore.self) private var prefs
    let track: UnifiedTrack
    var rank: Int? = nil
    var statText: String? = nil
    var isEnabled = true
    var onTap: () -> Void
    @State private var showingActions = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let rank {
                    Text("\(rank)")
                        .font(Typography.semibold(13))
                        .foregroundStyle(theme.palette.textMuted)
                        .frame(width: 22, alignment: .center)
                }
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).font(Typography.semibold(15))
                        .foregroundStyle(theme.palette.text).lineLimit(1)
                    HStack(spacing: 5) {
                        ProviderBadge(id: track.providerID, size: 16)
                        Text(track.artistNames).font(Typography.body(12))
                            .foregroundStyle(theme.palette.textSecondary).lineLimit(1)
                        if prefs.weight(for: track.uri) != 0 {
                            Text(weightBadge)
                                .font(Typography.body(11))
                                .foregroundStyle(theme.palette.rose)
                        }
                    }
                }
                Spacer(minLength: 4)
                if let statText {
                    Text(statText)
                        .font(Typography.semibold(12))
                        .foregroundStyle(theme.palette.textMuted)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
        .onLongPressGesture(minimumDuration: 0.4) {
            showingActions = true
        }
        .sheet(isPresented: $showingActions) {
            HeartableChoiceSheet(
                title: track.name,
                subtitle: "Adjust how often this song appears in Weighted mode.",
                items: [
                    HeartableChoiceItem(
                        id: "boost",
                        icon: "arrow.up",
                        title: "Boost in shuffle"
                    ),
                    HeartableChoiceItem(
                        id: "downvote",
                        icon: "arrow.down",
                        title: "Downvote in shuffle"
                    ),
                    HeartableChoiceItem(
                        id: "reset",
                        icon: "arrow.counterclockwise",
                        title: "Reset shuffle weight",
                        isDisabled: prefs.weight(for: track.uri) == 0
                    ),
                ],
                onCancel: { showingActions = false },
                onSelect: { item in
                    switch item.id {
                    case "boost": prefs.bump(track.uri, by: 10)
                    case "downvote": prefs.bump(track.uri, by: -10)
                    case "reset": prefs.setWeight(track.uri, to: 0)
                    default: break
                    }
                    showingActions = false
                }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(track.name)
        .accessibilityValue(
            [track.artistNames, providerLabel, statText]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        .accessibilityHint(
            isEnabled
                ? "Plays track. More actions available"
                : "Connect this music service to play"
        )
        .accessibilityActions {
            weightActions
        }
        .padding(.vertical, 6)
    }

    private var providerLabel: String {
        ProviderCatalog.entry(track.providerID)?.label ?? track.providerID.rawValue
    }

    @ViewBuilder
    private var weightActions: some View {
        Button {
            prefs.bump(track.uri, by: 10)
        } label: {
            Label("Boost in shuffle", systemImage: "arrow.up")
        }
        Button {
            prefs.bump(track.uri, by: -10)
        } label: {
            Label("Downvote in shuffle", systemImage: "arrow.down")
        }
        if prefs.weight(for: track.uri) != 0 {
            Button {
                prefs.setWeight(track.uri, to: 0)
            } label: {
                Label("Reset shuffle weight", systemImage: "arrow.counterclockwise")
            }
        }
    }

    private var weightBadge: String {
        let w = prefs.weight(for: track.uri)
        return w > 0 ? "↑\(w)" : "↓\(-w)"
    }

    private var artwork: some View {
        CoverArt(url: track.albumArt, size: 48)
    }
}
