import SwiftUI

/// Connect/disconnect every music service in one compact list. Each row shows the
/// real service logo, a per-feature capability key (lit when the service's API
/// supports it, greyed when it doesn't), and a connect control. Non-live services
/// open a setup sheet with what's needed to wire them.
struct MusicServicesView: View {
    @Environment(ProvidersStore.self) private var providers
    @Environment(ThemeStore.self) private var theme
    @Environment(BannerCenter.self) private var banners
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var busy: ProviderID?
    @State private var setupEntry: ProviderCatalogEntry?
    @State private var lastfmPromptShown = false
    @State private var lastfmUsername = ""
    @State private var listenbrainzPromptShown = false
    @State private var listenbrainzUsername = ""
    @State private var jellyfinSheetShown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                legend
                VStack(spacing: 8) {
                    ForEach(ProviderCatalog.all.filter { $0.id != .heartable }) { row($0) }
                }
            }
            .padding(16)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle("Music Services")
        .navigationBarTitleDisplayMode(.inline)
        .task { await providers.refresh() }
        .sheet(item: $setupEntry) { entry in
            ServiceSetupSheet(entry: entry).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $jellyfinSheetShown) {
            JellyfinConnectSheet().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $lastfmPromptShown) {
            HeartablePromptSheet(
                icon: "chart.bar.fill",
                title: "Last.fm username",
                message: "Heartable reads this account’s public scrobbles.",
                placeholder: "username",
                text: $lastfmUsername,
                actionTitle: "Connect",
                autocapitalization: .never,
                autocorrectionDisabled: true,
                onCancel: { lastfmPromptShown = false },
                onSubmit: {
                    LastfmProvider.setUsername(lastfmUsername)
                    lastfmPromptShown = false
                    if let entry = ProviderCatalog.entry(.lastfm) {
                        performToggle(entry, connected: false)
                    }
                }
            )
        }
        .sheet(isPresented: $listenbrainzPromptShown) {
            HeartablePromptSheet(
                icon: "waveform.path.ecg",
                title: "ListenBrainz username",
                message: "Heartable reads this account’s public listens.",
                placeholder: "username",
                text: $listenbrainzUsername,
                actionTitle: "Connect",
                autocapitalization: .never,
                autocorrectionDisabled: true,
                onCancel: { listenbrainzPromptShown = false },
                onSubmit: {
                    ListenBrainzProvider.setUsername(listenbrainzUsername)
                    listenbrainzPromptShown = false
                    if let entry = ProviderCatalog.entry(.listenbrainz) {
                        performToggle(entry, connected: false)
                    }
                }
            )
        }
    }

    // MARK: - Capability key

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHAT EACH SERVICE CAN DO")
                .font(Typography.semibold(11)).tracking(1)
                .foregroundStyle(theme.palette.textMuted)
            capabilityKey
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    @ViewBuilder
    private var capabilityKey: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: 10)],
                alignment: .leading,
                spacing: 8
            ) {
                capabilityLegendItems
            }
        } else {
            HStack(spacing: 4) {
                capabilityLegendItems
            }
        }
    }

    @ViewBuilder
    private var capabilityLegendItems: some View {
        ForEach(ProviderCapabilities.ordered, id: \.label) { item in
            HStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(
                        dynamicTypeSize.isAccessibilitySize
                            ? .caption.weight(.semibold)
                            : .system(size: 10, weight: .semibold)
                    )
                Text(item.label)
                    .font(
                        dynamicTypeSize.isAccessibilitySize
                            ? Typography.medium(13)
                            : Typography.medium(10)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(
                        dynamicTypeSize.isAccessibilitySize ? 1 : 0.72
                    )
                    .allowsTightening(true)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(theme.palette.textSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.label) capability")
        }
    }

    // MARK: - Row

    private func row(_ entry: ProviderCatalogEntry) -> some View {
        let connected = providers.isConnected(entry.id)
        let live = entry.status == .live
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ProviderBadge(id: entry.id, size: 34, connected: connected)
                        Text(entry.label).font(Typography.semibold(15))
                            .foregroundStyle(theme.palette.text)
                    }
                    capabilityIcons(entry)
                    control(entry, connected: connected, live: live)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 12) {
                    ProviderBadge(id: entry.id, size: 34, connected: connected)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.label).font(Typography.semibold(15))
                            .foregroundStyle(theme.palette.text).lineLimit(1)
                        capabilityIcons(entry)
                    }
                    Spacer(minLength: 6)
                    control(entry, connected: connected, live: live)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(connected ? theme.palette.rose.opacity(0.5) : theme.palette.border, lineWidth: 1)
        )
    }

    /// The five feature icons, lit in the brand color when the API supports them.
    private func capabilityIcons(_ entry: ProviderCatalogEntry) -> some View {
        HStack(spacing: 9) {
            ForEach(ProviderCapabilities.ordered, id: \.label) { item in
                let on = entry.capabilities.contains(item.cap)
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(on ? entry.brandColor : theme.palette.textMuted.opacity(0.4))
                    .frame(minWidth: 24, minHeight: 24)
                    .accessibilityLabel(item.label)
                    .accessibilityValue(on ? "Supported" : "Not supported")
            }
        }
    }

    @ViewBuilder
    private func control(_ entry: ProviderCatalogEntry, connected: Bool, live: Bool) -> some View {
        if busy == entry.id {
            ProgressView().controlSize(.small)
        } else if live {
            Button(connected ? "Disconnect" : "Connect") {
                toggle(entry, connected: connected)
            }
            .font(Typography.semibold(13))
            .foregroundStyle(connected ? theme.palette.textSecondary : .white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .frame(minHeight: 44)
            .background(connected ? theme.palette.surface : theme.palette.rose, in: Capsule())
        } else {
            Button { setupEntry = entry } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.palette.textMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Setup information for \(entry.label)")
        }
    }

    private func toggle(_ entry: ProviderCatalogEntry, connected: Bool) {
        // Last.fm needs a username before its first connect — ask in place
        // (prefilled, so this is also how you switch accounts later).
        if entry.id == .lastfm, !connected {
            lastfmUsername = LastfmProvider.username ?? ""
            lastfmPromptShown = true
            return
        }
        if entry.id == .listenbrainz, !connected {
            listenbrainzUsername = ListenBrainzProvider.username ?? ""
            listenbrainzPromptShown = true
            return
        }
        // Jellyfin needs a server address + sign-in — a dedicated sheet, since
        // three fields don't fit an alert.
        if entry.id == .jellyfin, !connected {
            jellyfinSheetShown = true
            return
        }
        performToggle(entry, connected: connected)
    }

    private func performToggle(_ entry: ProviderCatalogEntry, connected: Bool) {
        busy = entry.id
        Task {
            let provider = ProviderRegistry.provider(for: entry.id)
            do {
                if connected {
                    await provider.disconnect()
                    banners.info("Disconnected \(entry.label)")
                } else {
                    try await provider.connect()
                    banners.success("Connected \(entry.label)")
                }
            } catch {
                banners.error(error.localizedDescription)
            }
            await providers.refresh()
            busy = nil
        }
    }
}

// MARK: - Setup sheet (non-live services)

private struct ServiceSetupSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.openURL) private var openURL
    let entry: ProviderCatalogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProviderBadge(id: entry.id, size: 44, connected: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.label).font(Typography.heading(22))
                            .foregroundStyle(theme.palette.text)
                        Text(statusLabel).font(Typography.semibold(12))
                            .foregroundStyle(theme.palette.textMuted)
                    }
                }

                Text(entry.blurb)
                    .font(Typography.body(14))
                    .foregroundStyle(theme.palette.textSecondary)

                if !entry.setupSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SETUP").font(Typography.semibold(11)).tracking(1)
                            .foregroundStyle(theme.palette.textMuted)
                        ForEach(Array(entry.setupSteps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(i + 1).").font(Typography.semibold(13))
                                    .foregroundStyle(theme.palette.rose)
                                Text(step).font(Typography.body(13))
                                    .foregroundStyle(theme.palette.text)
                            }
                        }
                    }
                }

                if let url = entry.setupURL {
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Open developer docs").font(Typography.semibold(14))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.palette.rose, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(theme.palette.bg.ignoresSafeArea())
    }

    private var statusLabel: String {
        switch entry.status {
        case .live: "Available now"
        case .stubbed: "Needs credentials"
        case .comingSoon: "Coming soon"
        }
    }
}
