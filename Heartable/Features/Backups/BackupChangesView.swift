import SwiftUI

struct BackupSnapshotReference: Hashable {
    let id: UUID
    let name: String
    let createdAt: String?
    let expectedTrackCount: Int

    init(_ snapshot: LibrarySnapshotDTO) {
        id = snapshot.id
        name = snapshot.name?.isEmpty == false ? snapshot.name! : "Heartable backup"
        createdAt = snapshot.createdAt
        expectedTrackCount = (snapshot.trackCount ?? 0) + (snapshot.likedCount ?? 0)
    }
}

struct BackupDiffSelection: Hashable, Identifiable {
    let current: BackupSnapshotReference
    let previous: BackupSnapshotReference?

    var id: UUID { current.id }
}

struct BackupChangesView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let selection: BackupDiffSelection

    @State private var difference = BackupSnapshotDifference(added: [], removed: [])
    @State private var loading = true
    @State private var failed = false
    @State private var excludedProviders: [ProviderID] = []
    @State private var hasSharedServices = true

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    comparisonSummary
                    if !excludedProviders.isEmpty, !loading, !failed {
                        Text(excludedServiceMessage)
                            .font(Typography.body(13))
                            .foregroundStyle(theme.palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if selection.previous == nil {
                        firstBackupState
                    } else if loading {
                        ProgressView()
                            .tint(theme.palette.rose)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if failed {
                        messageState(
                            icon: "exclamationmark.arrow.triangle.2.circlepath",
                            text: "Couldn’t load the complete comparison."
                        )
                        Button("Try again") { Task { await loadDifference() } }
                            .font(Typography.semibold(14))
                            .foregroundStyle(theme.palette.rose)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else if difference.added.isEmpty, difference.removed.isEmpty {
                        messageState(
                            icon: "checkmark.circle.fill",
                            text: hasSharedServices ? "No songs were added or removed in the compared services." : "No shared services to compare."
                        )
                    } else {
                        changeSection(
                            title: "Added",
                            icon: "plus",
                            tint: theme.palette.emerald,
                            items: difference.added
                        )
                        changeSection(
                            title: "Removed",
                            icon: "minus",
                            tint: theme.palette.danger,
                            items: difference.removed
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .refreshable { await loadDifference() }
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { MainThreadStallMonitor.note("open backup changes") }
        .task(id: selection.id) { await loadDifference() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HeartableNavigationButton(kind: .back, action: dismiss.callAsFunction)
            Text("Changes")
                .font(Typography.heading(25))
                .foregroundStyle(theme.palette.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background(theme.palette.bg)
    }

    private var comparisonSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.current.name)
                    .font(Typography.semibold(17))
                    .foregroundStyle(theme.palette.text)
                Text(comparisonSubtitle)
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textSecondary)
            }

            if selection.previous != nil, !loading, !failed {
                HStack(spacing: 10) {
                    changeCount(
                        difference.added.count,
                        label: "added",
                        icon: "plus",
                        tint: theme.palette.emerald
                    )
                    changeCount(
                        difference.removed.count,
                        label: "removed",
                        icon: "minus",
                        tint: theme.palette.danger
                    )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(theme.palette.border, lineWidth: 1)
        }
    }

    private var comparisonSubtitle: String {
        guard let previous = selection.previous else {
            return "This is the first saved version of your library."
        }
        if let timestamp = previous.createdAt {
            let relative = relativeLong(timestamp)
            if !relative.isEmpty { return "Compared with \(relative)" }
        }
        return "Compared with \(previous.name)"
    }

    private var excludedServiceMessage: String {
        let names = excludedProviders.map { ProviderCatalog.label(for: $0) }
            .joined(separator: ", ")
        return "Not compared: \(names). These services don’t appear in both saved backups."
    }

    private var firstBackupState: some View {
        messageState(
            icon: "sparkles",
            text: "Future backups will show added and removed songs here."
        )
    }

    private func messageState(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(theme.palette.rose)
            Text(text)
                .font(Typography.body(13))
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func changeCount(_ count: Int, label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text("\(count) \(label)")
                .font(Typography.semibold(12))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func changeSection(
        title: String,
        icon: String,
        tint: Color,
        items: [BackupInventoryItem]
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                    Text(title.uppercased())
                        .font(Typography.semibold(12))
                        .tracking(1)
                    Text("\(items.count)")
                        .font(Typography.semibold(10))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.12), in: Capsule())
                }
                .foregroundStyle(tint)

                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        changeRow(item, action: title == "Added" ? "Added to" : "Removed from")
                        if index < items.count - 1 {
                            Divider()
                                .overlay(theme.palette.border)
                                .padding(.leading, 58)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .stroke(theme.palette.border, lineWidth: 1)
                }
            }
        }
    }

    private func changeRow(_ item: BackupInventoryItem, action: String) -> some View {
        HStack(spacing: 10) {
            CoverArt(
                url: item.artworkURL.flatMap(URL.init(string:)),
                size: 42,
                corner: 8
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name?.isEmpty == false ? item.name! : "Saved track")
                    .font(Typography.medium(13))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
                Text(item.artist?.isEmpty == false ? item.artist! : "Unknown artist")
                    .font(Typography.body(11))
                    .foregroundStyle(theme.palette.textMuted)
                    .lineLimit(1)
                Text("\(action) \(item.collection)")
                    .font(Typography.medium(12))
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let provider = item.providerID {
                    Text(ProviderCatalog.label(for: provider))
                        .font(Typography.body(11))
                        .foregroundStyle(theme.palette.textMuted)
                }
            }

            Spacer(minLength: 4)

            if let providerID = item.providerID {
                ProviderBadge(id: providerID, size: 18)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func loadDifference() async {
        guard let previous = selection.previous else {
            loading = false
            return
        }

        loading = true
        failed = false
        do {
            async let currentLoad = BackupInventoryLoader.load(snapshotID: selection.current.id)
            async let previousLoad = BackupInventoryLoader.load(snapshotID: previous.id)
            let (current, prior) = try await (currentLoad, previousLoad)
            guard current.count == selection.current.expectedTrackCount,
                  prior.count == previous.expectedTrackCount else {
                failed = true
                loading = false
                return
            }
            let scope = BackupComparisonScope(current: current, previous: prior)
            excludedProviders = scope.excludedProviders.sorted { $0.rawValue < $1.rawValue }
            hasSharedServices = !scope.sharedProviders.isEmpty
            difference = BackupSnapshotDiffer.difference(
                current: current.filter(scope.includes), previous: prior.filter(scope.includes)
            )
        } catch {
            failed = true
        }
        loading = false
    }
}
