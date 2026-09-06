import SwiftUI

/// Account libraries, listening-history connections and always-available public search
/// sources are deliberately separate. Unimplemented services have no fake controls.
struct MusicServicesView: View {
    @Environment(ProvidersStore.self) private var providers
    @Environment(ThemeStore.self) private var theme
    @Environment(BannerCenter.self) private var banners
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var busy: ProviderID?
    @State private var lastfmPromptShown = false
    @State private var lastfmUsername = ""
    @State private var jellyfinSheetShown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                legend
                providerSection(.library)
                searchSources
                if !ProviderCatalog.entries(in: .history).isEmpty { providerSection(.history) }
            }
            .padding(16)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle("Music Services")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Account bootstrap owns the initial probe. This is only a later
            // foreground re-check and must not race restoration metadata.
            if !providers.isRestoring { await providers.refresh() }
        }
        .sheet(isPresented: $jellyfinSheetShown) {
            JellyfinConnectSheet()
                .heartableSheetChrome()
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

    }

    private func providerSection(_ section: ProviderSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(section.rawValue)
            ForEach(ProviderCatalog.entries(in: section)) { row($0) }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title).font(Typography.semibold(14))
            .foregroundStyle(theme.palette.textSecondary).padding(.top, 10)
    }

    private var searchSources: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Search")
            HStack(spacing: 0) {
                ForEach(ProviderCatalog.publicSearchIDs.filter { $0 != .wsum }) { id in
                    ProviderLogo(id: id, size: 48)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(ProviderCatalog.entry(id)?.label ?? id.rawValue)
                        .accessibilityValue("Available in search")
                }
            }
            .padding(.vertical, 18)
            .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(theme.palette.border))
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
        let reconnectRequired = providers.requiresReconnect(entry.id)
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
                    control(
                        entry,
                        connected: connected,
                        live: live,
                        reconnectRequired: reconnectRequired
                    )
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
                    control(
                        entry,
                        connected: connected,
                        live: live,
                        reconnectRequired: reconnectRequired
                    )
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
    private func control(
        _ entry: ProviderCatalogEntry,
        connected: Bool,
        live: Bool,
        reconnectRequired: Bool
    ) -> some View {
        if busy == entry.id || (providers.isRestoring && !connected) {
            ProgressView().controlSize(.small)
        } else if live {
            Button(connected ? "Disconnect" : (reconnectRequired ? "Reconnect" : "Connect")) {
                toggle(entry, connected: connected)
            }
            .font(Typography.semibold(13))
            .foregroundStyle(connected ? theme.palette.textSecondary : .white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .frame(minHeight: 44)
            .background(connected ? theme.palette.surface : theme.palette.rose, in: Capsule())
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
            do {
                if connected {
                    await providers.disconnect(entry.id)
                    banners.info("Disconnected \(entry.label)")
                } else {
                    try await providers.connect(entry.id)
                    banners.success("Connected \(entry.label)")
                }
            } catch {
                banners.error(error.localizedDescription)
            }
            busy = nil
        }
    }
}
