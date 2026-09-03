import SwiftUI

/// Every track the user has played, newest first. Swipe a row to delete it; the
/// toolbar trash clears the whole log (with confirmation). A banner reminds the
/// user when Ghost Mode is suppressing new captures.
struct ListeningHistoryView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlaybackPrefsStore.self) private var prefs
    @Environment(TopTracksRepository.self) private var topTracks
    @Environment(BannerCenter.self) private var banners

    @State private var history: [PlayEntryDTO] = []
    @State private var loading = true
    @State private var confirmClear = false
    @State private var clearingHistory = false
    @State private var showingGhostDurations = false

    var body: some View {
        // A List (not a ScrollView) so per-row swipe-to-delete actually works.
        List {
            ghostModeCard
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if loading {
                ProgressView()
                    .tint(theme.palette.rose)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if history.isEmpty {
                Text("Nothing here yet. Play a track and it'll land here.")
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textMuted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                historyHeader
                    .listRowInsets(EdgeInsets(top: 14, leading: 18, bottom: 6, trailing: 18))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                ForEach(history) { entry in
                    row(entry)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await delete(entry) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle("Listening History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    confirmClear = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.palette.rose)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(theme.palette.roseDim)
                                .frame(width: 32, height: 32)
                        )
                }
                .disabled(history.isEmpty)
                .accessibilityLabel("Clear listening history")
            }
        }
        .sheet(isPresented: $confirmClear) {
            HeartableDestructiveConfirmation(
                icon: "trash.fill",
                title: "Clear listening history?",
                message: clearHistoryMessage,
                confirmTitle: "Clear history",
                cancelTitle: "Keep history",
                isBusy: clearingHistory,
                onCancel: {
                    confirmClear = false
                },
                onConfirm: {
                    clearingHistory = true
                    Task { await clearAll() }
                }
            )
        }
        .sheet(isPresented: $showingGhostDurations) {
            GhostModeDurationSheet(
                isEnabled: prefs.ghostMode,
                onSelect: { duration in
                    prefs.enableGhostMode(for: duration)
                    showingGhostDurations = false
                    banners.info("Ghost Mode \(prefs.ghostModeStatus().lowercased()).")
                },
                onDisable: {
                    prefs.disableGhostMode()
                    showingGhostDurations = false
                    banners.info("Ghost Mode off. New plays will be recorded.")
                }
            )
        }
        .task {
            prefs.refreshGhostMode()
            await load()
        }
    }

    // MARK: - Rows

    private var historyHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Recent plays")
                .font(Typography.semibold(12))
                .foregroundStyle(theme.palette.text)
                .textCase(.uppercase)
                .tracking(0.8)
            Text("Newest first · swipe a play to remove it")
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private var ghostModeCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(prefs.ghostMode ? theme.palette.rose : theme.palette.surface)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: prefs.ghostMode ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(
                                prefs.ghostMode ? .white : theme.palette.textSecondary
                            )
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ghost Mode")
                        .font(Typography.semibold(15))
                        .foregroundStyle(theme.palette.text)
                    Text(prefs.ghostModeStatus())
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }

            Button {
                showingGhostDurations = true
            } label: {
                Text(prefs.ghostMode ? "Change duration" : "Choose duration")
                    .font(Typography.semibold(13))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(theme.palette.rose, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose how long new plays stay out of listening history")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(theme.palette.border, lineWidth: 1)
        }
    }

    private func row(_ entry: PlayEntryDTO) -> some View {
        HStack(spacing: 12) {
            CoverArt(url: entry.albumArt.flatMap(URL.init(string:)), size: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.trackName ?? "Unknown track")
                    .font(Typography.semibold(14))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
                Text(entry.artist ?? "Unknown artist")
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
                Text(relativeLong(entry.playedAt ?? ""))
                    .font(Typography.body(11))
                    .foregroundStyle(theme.palette.textMuted)
            }
            Spacer(minLength: 4)
        }
        .padding(12)
        .background(
            theme.palette.card,
            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(theme.palette.border, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Delete from listening history") {
            Task { await delete(entry) }
        }
    }

    // MARK: - Data

    private var clearHistoryMessage: String {
        "All recorded plays for this account will be removed. Your stats and leaderboard contributions will reset."
    }

    private func load() async {
        loading = true
        history = await BackendAPI.shared.fetchPlayHistory(limit: 200)
        loading = false
    }

    private func delete(_ entry: PlayEntryDTO) async {
        do {
            try await BackendAPI.shared.deletePlayEntries(ids: [entry.id])
            history.removeAll { $0.id == entry.id }
            await topTracks.invalidateHistory()
            for (index, range) in StatRange.allCases.enumerated() {
                await topTracks.load(
                    range: range,
                    providers: [],
                    force: index == 0
                )
            }
        } catch {
            banners.error("Couldn't remove that play. Please try again.")
        }
    }

    private func clearAll() async {
        do {
            try await BackendAPI.shared.clearPlayHistory()
            history = []
            await topTracks.invalidateHistory()
            clearingHistory = false
            confirmClear = false
            banners.success("Listening history cleared.")
        } catch {
            clearingHistory = false
            banners.error("Couldn't clear listening history. Please try again.")
        }
    }
}

private struct GhostModeDurationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isEnabled: Bool
    let onSelect: (GhostModeDuration) -> Void
    let onDisable: () -> Void

    private var items: [HeartableChoiceItem] {
        var options = GhostModeDuration.allCases.map { duration in
            HeartableChoiceItem(
                id: duration.rawValue,
                icon: duration.systemImage,
                title: duration.title
            )
        }
        if isEnabled {
            options.append(HeartableChoiceItem(
                id: "disable",
                icon: "eye.fill",
                title: "Turn off Ghost Mode",
                isDestructive: true
            ))
        }
        return options
    }

    var body: some View {
        HeartableChoiceSheet(
            title: "Ghost Mode",
            subtitle: "New plays stay private while Ghost Mode is on.",
            items: items,
            onCancel: { dismiss() },
            onSelect: { item in
                if item.id == "disable" {
                    onDisable()
                } else if let duration = GhostModeDuration(rawValue: item.id) {
                    onSelect(duration)
                }
            }
        )
    }
}
