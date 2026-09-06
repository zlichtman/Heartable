import SwiftUI
import UniformTypeIdentifiers

/// Backups — a focused protection dashboard: create a snapshot from selected
/// connected services, choose an automatic cadence, import/export CSV, and browse
/// restorable history. Restoring currently targets Spotify; capture supports every
/// live provider represented by the local snapshot importer.
struct BackupsView: View {
    private enum HistoryMode: String, CaseIterable, Identifiable {
        case history = "History"
        case changes = "Changes"

        var id: String { rawValue }
    }

    private enum PendingBackupAction {
        case restore(UUID)
        case delete(UUID)
        case rename(LibrarySnapshotDTO)
    }
    @Environment(ThemeStore.self) private var theme
    @Environment(ProvidersStore.self) private var providers
    @Environment(BannerCenter.self) private var banners
    @Environment(BackupScheduler.self) private var backupScheduler

    @State private var snapshots: [LibrarySnapshotDTO] = []
    @State private var loaded = false

    // The true service set per snapshot, derived from its captured contents' uris.
    // This overrides the stored `providers` column, which on legacy snapshots was
    // written with the full selected set rather than only what actually landed.
    @State private var derivedProviders: [UUID: [ProviderID]] = [:]

    // Capture state.
    @State private var capturing = false

    // CSV import state.
    @State private var importing = false
    @State private var showImporter = false

    // Per-snapshot transient state.
    @State private var expandedID: UUID?
    @State private var playlists: [SnapshotPlaylistDTO] = []
    @State private var likedCount = 0
    @State private var detailLoading = false
    @State private var detailFailed = false
    @State private var detailRequest = UUID()
    @State private var detailCache: [UUID: ([SnapshotPlaylistDTO], Int)] = [:]
    @State private var selectedContent: BackupContentSelection?
    @State private var selectedDiff: BackupDiffSelection?
    @State private var historyMode: HistoryMode = .history
    @State private var restoringID: UUID?
    @State private var deletingID: UUID?

    // Confirmation alerts (carry the target snapshot id).
    @State private var confirmDeleteID: UUID?
    @State private var confirmRestoreID: UUID?
    @State private var actionSnapshot: LibrarySnapshotDTO?
    @State private var pendingBackupAction: PendingBackupAction?
    @State private var renameSnapshot: LibrarySnapshotDTO?
    @State private var backupName = ""
    @State private var renaming = false

    // Scheduled capture preference, consumed by BackupScheduler on launch/foreground.
    @State private var frequency = BackupFrequency.manual.rawValue

    // Bumped on each service-chip tap so the view re-reads the persisted selection.
    @State private var selectionTick = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        backupOverview
                        backupPreferences
                        backupsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .background(theme.palette.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedContent) { selection in
                BackupContentsView(selection: selection)
            }
            .navigationDestination(item: $selectedDiff) { selection in
                BackupChangesView(selection: selection)
            }
        }
        .task {
            guard !loaded else { return }
            frequency = AccountSessionStore.defaultString(
                forKey: "heartable.backup.frequency"
            ) ?? BackupFrequency.manual.rawValue
            await reload()
            loaded = true
        }
        .onChange(of: frequency) { _, value in
            AccountSessionStore.setDefault(
                value,
                forKey: "heartable.backup.frequency"
            )
        }
        .refreshable { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .heartableBackupCreated)) { event in
            guard event.object as? UUID == AccountSessionStore.currentOwnerID else { return }
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .heartableMusicDataCleared)) { event in
            guard event.object as? UUID == AccountSessionStore.currentOwnerID else { return }
            snapshots = []
            derivedProviders = [:]
            expandedID = nil
            detailCache = [:]
            detailRequest = UUID()
            selectedContent = nil
            selectedDiff = nil
        }
        .sheet(isPresented: restoreAlertBinding) {
            HeartableDestructiveConfirmation(
                icon: "arrow.uturn.backward",
                title: "Restore backup?",
                message: "Recreates this backup’s playlists and liked songs in your Spotify account.",
                confirmTitle: "Restore",
                cancelTitle: "Not now",
                tone: .accent,
                isBusy: restoringID != nil,
                onCancel: { confirmRestoreID = nil },
                onConfirm: {
                    guard let id = confirmRestoreID else { return }
                    Task { await restore(id) }
                }
            )
        }
        .sheet(isPresented: deleteAlertBinding) {
            HeartableDestructiveConfirmation(
                icon: "trash.fill",
                title: "Delete backup?",
                message: "This permanently deletes this backup and all of its captured data.",
                confirmTitle: "Delete backup",
                cancelTitle: "Keep backup",
                isBusy: deletingID != nil,
                onCancel: { confirmDeleteID = nil },
                onConfirm: {
                    guard let id = confirmDeleteID else { return }
                    Task { await delete(id) }
                }
            )
        }
        .sheet(
            item: $actionSnapshot,
            onDismiss: presentPendingBackupAction
        ) { snapshot in
            BackupActionsSheet(
                snapshot: snapshot,
                exportName: csvName(snapshot),
                isRestoring: restoringID == snapshot.id,
                onClose: { actionSnapshot = nil },
                onRename: {
                    pendingBackupAction = .rename(snapshot)
                    actionSnapshot = nil
                },
                onRestore: {
                    pendingBackupAction = .restore(snapshot.id)
                    actionSnapshot = nil
                },
                onDelete: {
                    pendingBackupAction = .delete(snapshot.id)
                    actionSnapshot = nil
                }
            )
        }
        .sheet(item: $renameSnapshot) { snapshot in
            HeartablePromptSheet(
                icon: "pencil",
                title: "Rename backup",
                message: "",
                placeholder: "Backup name",
                text: $backupName,
                actionTitle: "Save",
                isBusy: renaming,
                onCancel: { renameSnapshot = nil },
                onSubmit: { Task { await rename(snapshot) } }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HeartablePageHeader(tab: .backups)
    }

    // MARK: - Overview + preferences

    private var connectedEntries: [ProviderCatalogEntry] {
        ProviderCatalog.all.filter { providers.isConnected($0.id) }
    }

    /// Providers the user has both connected and left selected for backup.
    private var selectedProviderIDs: [ProviderID] {
        connectedEntries.map(\.id).filter { isServiceSelected($0) }
    }

    private var latestSnapshot: LibrarySnapshotDTO? { snapshots.first }

    private var backupOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    Circle()
                        .fill(theme.palette.rose.opacity(0.14))
                    Image(systemName: !loaded
                          ? "clock.arrow.circlepath"
                          : snapshots.isEmpty
                          ? "externaldrive.fill.badge.plus"
                          : "checkmark.shield.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.palette.rose)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(overviewTitle)
                        .font(Typography.semibold(17))
                        .foregroundStyle(theme.palette.text)
                    Text(overviewSubtitle)
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button {
                Task { await capture() }
            } label: {
                HStack(spacing: 8) {
                    if capturing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "externaldrive.fill.badge.plus")
                    }
                    Text(capturing ? "Creating backup…" : "Back Up Now")
                        .font(Typography.semibold(15))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(theme.palette.rose, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .opacity(captureDisabled ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(captureDisabled)

            if selectedProviderIDs.isEmpty {
                Text(connectedEntries.isEmpty
                     ? "Connect a music service before creating a backup."
                     : "Choose at least one service in Backup Settings.")
                    .font(Typography.body(11))
                    .foregroundStyle(theme.palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
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

    private var overviewTitle: String {
        if !loaded { return "Checking your backups…" }
        return snapshots.isEmpty ? "Create your first backup" : "Your library is protected"
    }

    private var overviewSubtitle: String {
        guard loaded else { return "Looking for your most recent snapshot." }
        guard let latest = latestSnapshot else {
            return "Save your playlists and liked songs in one restorable snapshot."
        }
        let date = latest.createdAt.map(relativeLong) ?? ""
        let counts = countsLine(latest)
        return date.isEmpty ? counts : "Last backup \(date) · \(counts)"
    }

    private var backupPreferences: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                settingsIcon("calendar.badge.clock")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic backups")
                        .font(Typography.semibold(14))
                        .foregroundStyle(theme.palette.text)
                    Text(frequency == BackupFrequency.manual.rawValue
                         ? "Off"
                         : "Checked when Heartable opens")
                        .font(Typography.body(11))
                        .foregroundStyle(theme.palette.textMuted)
                }
                Spacer()
                Picker("Automatic backups", selection: $frequency) {
                    ForEach(BackupFrequency.allCases) { item in
                        Text(item.label).tag(item.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.palette.rose)
            }
            .padding(14)

            Divider().overlay(theme.palette.border)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    settingsIcon("music.note.list")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Included services")
                            .font(Typography.semibold(14))
                            .foregroundStyle(theme.palette.text)
                        Text("Playlists and liked songs")
                            .font(Typography.body(11))
                            .foregroundStyle(theme.palette.textMuted)
                    }
                }

                let entries = connectedEntries
                if entries.isEmpty {
                    Text("Connect a service in Music Services to include it.")
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                } else {
                    serviceChips(entries)
                }
            }
            .padding(14)

            Divider().overlay(theme.palette.border)

            importRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(theme.palette.border, lineWidth: 1)
        }
    }

    private func settingsIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.palette.rose)
            .frame(width: 34, height: 34)
            .background(theme.palette.rose.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    }

    private var captureDisabled: Bool {
        capturing || selectedProviderIDs.isEmpty
    }

    /// Connected services as tappable chips: a lit, ring-bordered chip is selected
    /// for backup; a greyed one is excluded. Defaults to selected.
    private func serviceChips(_ entries: [ProviderCatalogEntry]) -> some View {
        ChipFlowLayout(spacing: 10) {
            ForEach(entries) { entry in
                let on = isServiceSelected(entry.id)
                Button {
                    setServiceSelected(entry.id, !on)
                } label: {
                    HStack(spacing: 7) {
                        ProviderBadge(id: entry.id, size: 22, connected: on)
                        Text(entry.label)
                            .font(Typography.semibold(13))
                            .foregroundStyle(on ? theme.palette.text : theme.palette.textMuted)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .frame(minHeight: 44)
                    .background(on ? theme.palette.surface : .clear, in: Capsule())
                    .overlay(
                        Capsule().stroke(on ? theme.palette.rose.opacity(0.6) : theme.palette.border,
                                         lineWidth: 1)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.label)
                .accessibilityValue(on ? "Included in backups" : "Excluded from backups")
            }
        }
    }

    /// Per-provider opt-in flag, persisted under a stable key. Defaults to on.
    /// `@State selectionTick` forces a re-read after a tap (UserDefaults isn't observed).
    private func isServiceSelected(_ id: ProviderID) -> Bool {
        _ = selectionTick
        let key = "heartable.backup.service.\(id.rawValue)"
        return AccountSessionStore.defaultObject(forKey: key) as? Bool ?? true
    }

    private func setServiceSelected(_ id: ProviderID, _ value: Bool) {
        AccountSessionStore.setDefault(
            value,
            forKey: "heartable.backup.service.\(id.rawValue)"
        )
        selectionTick += 1
    }

    // MARK: - Backups list

    @ViewBuilder
    private var backupsSection: some View {
        HStack {
            sectionHeader("Backup history")
            Spacer()
            if loaded, !snapshots.isEmpty {
                Text("\(snapshots.count)")
                    .font(Typography.semibold(11))
                    .foregroundStyle(theme.palette.textMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(theme.palette.surface, in: Capsule())
            }
        }

        if loaded, !snapshots.isEmpty {
            Picker("Backup history view", selection: $historyMode) {
                ForEach(HistoryMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(theme.palette.rose)
        }

        if !loaded {
            ProgressView()
                .tint(theme.palette.rose)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if snapshots.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.palette.textMuted)
                Text("Your backup history will appear here.")
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else if historyMode == .history {
            ForEach(snapshots) { snap in
                snapshotCard(snap)
            }
        } else {
            changesList
        }
    }

    private var changesList: some View {
        VStack(spacing: 10) {
            ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                let prior = snapshots.indices.contains(index + 1) ? snapshots[index + 1] : nil
                Button {
                    selectedDiff = BackupDiffSelection(
                        current: BackupSnapshotReference(snapshot),
                        previous: prior.map(BackupSnapshotReference.init)
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: prior == nil ? "sparkles" : "arrow.left.arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.palette.rose)
                            .frame(width: 38, height: 38)
                            .background(theme.palette.roseDim, in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(snapshot.name?.isEmpty == false ? snapshot.name! : "Heartable backup")
                                .font(Typography.semibold(14))
                                .foregroundStyle(theme.palette.text)
                                .lineLimit(1)
                            Text(comparisonLabel(current: snapshot, previous: prior))
                                .font(Typography.body(11))
                                .foregroundStyle(theme.palette.textMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.palette.textMuted)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(theme.palette.border, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(prior == nil
                    ? "Explains that this is the first backup"
                    : "Shows songs added and removed since the prior backup")
            }
        }
    }

    private func comparisonLabel(
        current: LibrarySnapshotDTO,
        previous: LibrarySnapshotDTO?
    ) -> String {
        guard let previous else { return "First backup · no earlier comparison" }
        let date = previous.createdAt.map(relativeLong) ?? ""
        return date.isEmpty ? "Compared with the prior backup" : "Compared with \(date)"
    }

    // MARK: - CSV import

    private var importRow: some View {
        Group {
            Button {
                showImporter = true
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("square.and.arrow.down")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(importing ? "Importing…" : "Import from CSV")
                            .font(Typography.semibold(14))
                            .foregroundStyle(theme.palette.text)
                        Text("Create a backup from an exported library file")
                            .font(Typography.body(11))
                            .foregroundStyle(theme.palette.textMuted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    if importing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.palette.textSecondary)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.palette.textMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(importing)
        }
        .padding(14)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importCSV(from: url) }
            case .failure(let error):
                banners.error("Import failed. \(error.localizedDescription)")
            }
        }
    }

    private func snapshotCard(_ snap: LibrarySnapshotDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    Task { await toggleExpand(snap) }
                } label: {
                    cardHeader(snap)
                }
                .buttonStyle(.plain)

                snapshotMenu(snap)
            }

            if expandedID == snap.id {
                expandedDetail(for: snap)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(theme.palette.border, lineWidth: 1)
        )
    }

    private func cardHeader(_ snap: LibrarySnapshotDTO) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.palette.rose)
                .frame(width: 38, height: 38)
                .background(
                    theme.palette.rose.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(snap.name?.isEmpty == false ? snap.name! : "Unnamed snapshot")
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if let created = snap.createdAt, !relativeLong(created).isEmpty {
                        Text(relativeLong(created))
                        Text("·")
                    }
                    Text(compactCountsLine(snap))
                }
                .font(Typography.body(11))
                .foregroundStyle(theme.palette.textMuted)
                .lineLimit(1)

                providerChips(serviceIDs(for: snap))
            }
            Spacer(minLength: 4)
            Image(systemName: expandedID == snap.id ? "chevron.up" : "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.palette.textMuted)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(expandedID == snap.id ? "Collapses backup details" : "Shows backup details")
    }

    /// The distinct service set to badge for a snapshot. Prefers the set derived
    /// from the snapshot's actual captured contents (`derivedProviders`); until
    /// that loads, falls back to the stored `providers` column so the row is never
    /// blank. Only services really present in the snapshot appear, never every
    /// connected service. Deduped, preserving first-seen order.
    private func serviceIDs(for snap: LibrarySnapshotDTO) -> [ProviderID] {
        if let derived = derivedProviders[snap.id] { return derived }
        var seen = Set<ProviderID>()
        return (snap.providers ?? [])
            .compactMap { ProviderID(rawValue: $0) }
            .filter { seen.insert($0).inserted }
    }

    @ViewBuilder
    private func providerChips(_ ids: [ProviderID]) -> some View {
        if !ids.isEmpty {
            ChipFlowLayout(spacing: 6) {
                ForEach(ids) { id in
                    HStack(spacing: 5) {
                        ProviderBadge(id: id, size: 16)
                        Text(ProviderCatalog.entry(id)?.label ?? id.rawValue)
                            .font(Typography.semibold(10))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
            }
        }
    }

    private func snapshotMenu(_ snap: LibrarySnapshotDTO) -> some View {
        Button {
            actionSnapshot = snap
        } label: {
            ZStack {
                if restoringID == snap.id {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.palette.textSecondary)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Backup actions")
    }

    @ViewBuilder
    private func expandedDetail(for snapshot: LibrarySnapshotDTO) -> some View {
        Divider().overlay(theme.palette.border)

        VStack(alignment: .leading, spacing: 8) {
            if detailLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(theme.palette.rose)
                    Text("Loading backup…").font(Typography.body(12))
                        .foregroundStyle(theme.palette.textMuted)
                }.frame(minHeight: 44)
            } else if detailFailed {
                Button("Couldn't load backup. Tap to retry.") {
                    expandedID = nil
                    Task { await toggleExpand(snapshot) }
                }.font(Typography.body(12)).foregroundStyle(theme.palette.rose)
                    .frame(minHeight: 44)
            }
            if likedCount > 0 {
                Button {
                    selectedContent = .likedSongs(
                        snapshotID: snapshot.id,
                        snapshotName: snapshot.name,
                        count: likedCount
                    )
                } label: {
                    contentRow(
                        icon: "heart.fill",
                        title: "Liked Songs",
                        count: likedCount
                    )
                }
                .buttonStyle(.plain)
            }

            if playlists.isEmpty && !detailLoading && !detailFailed {
                Text(likedCount > 0 ? "No playlists in this backup." : "This backup is empty.")
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textMuted)
                    .padding(.vertical, 4)
            } else {
                ForEach(playlists) { pl in
                    Button {
                        selectedContent = .playlist(
                            id: pl.id,
                            name: pl.name,
                            imageURL: pl.imageUrl,
                            count: pl.trackCount ?? 0
                        )
                    } label: {
                        contentRow(
                            icon: "music.note.list",
                            title: pl.name?.isEmpty == false ? pl.name! : "Untitled playlist",
                            count: pl.trackCount ?? 0,
                            imageURL: pl.imageUrl.flatMap(URL.init(string:))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func contentRow(icon: String, title: String, count: Int, imageURL: URL? = nil) -> some View {
        HStack(spacing: 10) {
            CoverArt(url: imageURL, size: 44, corner: 9, placeholder: icon)

            Text(title)
                .font(Typography.medium(13))
                .foregroundStyle(theme.palette.text)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text("\(count)")
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textMuted)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.palette.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the tracks in this backup")
    }

    // MARK: - Atoms

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typography.semibold(12))
            .tracking(1)
            .foregroundStyle(theme.palette.textMuted)
    }

    // MARK: - Derived

    private var restoreAlertBinding: Binding<Bool> {
        Binding(get: { confirmRestoreID != nil }, set: { if !$0 { confirmRestoreID = nil } })
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { confirmDeleteID != nil }, set: { if !$0 { confirmDeleteID = nil } })
    }

    private func presentPendingBackupAction() {
        switch pendingBackupAction {
        case .restore(let id):
            confirmRestoreID = id
        case .delete(let id):
            confirmDeleteID = id
        case .rename(let snapshot):
            backupName = snapshot.name ?? ""
            renameSnapshot = snapshot
        case nil:
            break
        }
        pendingBackupAction = nil
    }

    private func countsLine(_ snap: LibrarySnapshotDTO) -> String {
        let p = snap.playlistCount ?? 0
        let t = snap.trackCount ?? 0
        let l = snap.likedCount ?? 0
        return "\(p) playlists \u{00B7} \(t) tracks \u{00B7} \(l) liked"
    }

    private func compactCountsLine(_ snap: LibrarySnapshotDTO) -> String {
        let playlists = snap.playlistCount ?? 0
        let tracks = (snap.trackCount ?? 0) + (snap.likedCount ?? 0)
        let playlistLabel = playlists == 1 ? "playlist" : "playlists"
        let trackLabel = tracks == 1 ? "song" : "songs"
        return "\(playlists) \(playlistLabel), \(tracks) \(trackLabel)"
    }

    private func csvName(_ snap: LibrarySnapshotDTO) -> String {
        let base = snap.name?.isEmpty == false ? snap.name! : "snapshot"
        let safe = base.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "heartable-backup-" + String(safe)
    }

    // MARK: - Data actions

    private func rename(_ snapshot: LibrarySnapshotDTO) async {
        guard !renaming else { return }
        renaming = true
        defer { renaming = false }
        do {
            let updated = try await BackendAPI.shared.renameSnapshot(id: snapshot.id, name: backupName)
            if let index = snapshots.firstIndex(where: { $0.id == updated.id }) {
                snapshots[index] = updated
            }
            renameSnapshot = nil
            banners.success("Backup renamed")
        } catch {
            banners.error((error as? LocalizedError)?.errorDescription ?? "Could not rename backup. Try again.")
        }
    }

    private func reload() async {
        let fetched = await BackendAPI.shared.fetchSnapshots()
        snapshots = fetched
        await deriveProviderSets(for: fetched)
    }

    /// Resolve each snapshot's true service set from its captured contents, so the
    /// label reflects only what actually landed in that snapshot (not the set the
    /// user had selected at capture time). The backend helper resolves the whole
    /// page with a fixed three-query batch.
    private func deriveProviderSets(for snaps: [LibrarySnapshotDTO]) async {
        let ids = snaps.map(\.id)
        let resolved = await BackendAPI.shared.snapshotProviderIDs(snapshotIDs: ids)
        // Empty can also mean a transient backend failure; retain the denormalized
        // snapshot metadata as the visible fallback in that case.
        derivedProviders = resolved.filter { !$0.value.isEmpty }
    }

    private func capture() async {
        let ids = selectedProviderIDs
        guard !ids.isEmpty else {
            banners.error("Pick at least one connected service to back up.")
            return
        }
        capturing = true
        defer { capturing = false }
        do {
            let result = try await backupScheduler.performManualCapture {
                try await BackendAPI.shared.captureSnapshot(providerIDs: ids)
            }
            await reload()
            let msg = "Backed up \(result.playlistCount) playlists, \(result.trackCount) tracks, \(result.likedCount) liked."
            banners.success(msg)
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? "Please try again."
            banners.error("Backup failed. \(detail)")
        }
    }

    /// Read a picked CSV, parse it, and write it into a new snapshot. Reports
    /// success/failure through the shared app-wide banner.
    private func importCSV(from url: URL) async {
        importing = true
        defer { importing = false }

        // Security-scoped access for files outside the app sandbox.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let text: String
        do {
            let data = try Data(contentsOf: url)
            text = String(decoding: data, as: UTF8.self)
        } catch {
            banners.error("Import failed. Could not read the file.")
            return
        }

        let rows = CSVImportParser.parse(text)
        guard !rows.isEmpty else {
            // Tell the user (and us) why: surface the columns we actually found so a
            // header mismatch ("Track URI" vs "uri", a JSON file, etc.) is obvious.
            let cols = CSVImportParser.headerColumns(text)
            let detail = cols.isEmpty
                ? "The file looked empty or wasn't a CSV."
                : "Couldn't find a track-URI column. Columns found: \(cols.joined(separator: ", "))."
            banners.error("Import failed. \(detail)")
            return
        }

        let name = BackupName.timestamp()
        do {
            let result = try await backupScheduler.performManualCapture {
                try await BackendAPI.shared.importSnapshotFromCSV(name: name, rows: rows)
            }
            await reload()
            banners.success("Imported \(result.playlistCount) playlists, \(result.trackCount) tracks.")
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? "Please try again."
            banners.error("Import failed. \(detail)")
        }
    }

    private func toggleExpand(_ snap: LibrarySnapshotDTO) async {
        if expandedID == snap.id {
            expandedID = nil
            detailRequest = UUID()
            return
        }
        let request = UUID()
        detailRequest = request
        let owner = AccountSessionStore.currentOwnerID
        detailFailed = false
        if let cached = detailCache[snap.id] {
            playlists = cached.0
            likedCount = cached.1
            detailLoading = false
            expandedID = snap.id
            return
        }
        detailLoading = true
        expandedID = snap.id
        playlists = []
        likedCount = snap.likedCount ?? 0
        do {
            async let pls = BackendAPI.shared.requireSnapshotPlaylists(snapshotID: snap.id)
            async let liked = BackendAPI.shared.requireSnapshotLikedTracks(snapshotID: snap.id)
            let (loadedPls, loadedLiked) = try await (pls, liked)
            guard detailRequest == request, AccountSessionStore.currentOwnerID == owner else { return }
            detailCache[snap.id] = (loadedPls, loadedLiked.count)
            playlists = loadedPls
            likedCount = loadedLiked.count
            detailLoading = false
        } catch {
            guard detailRequest == request, AccountSessionStore.currentOwnerID == owner else { return }
            detailLoading = false
            detailFailed = true
        }
    }

    private func restore(_ id: UUID) async {
        guard let token = await SpotifyAuth.getValidAccessToken() else {
            banners.error("Connect Spotify in Music Services to restore.")
            return
        }
        restoringID = id
        defer {
            restoringID = nil
            confirmRestoreID = nil
        }
        do {
            let result = try await BackendAPI.shared.restoreSnapshot(spotifyToken: token, snapshotID: id)
            let n = result.restored.count
            let noun = n == 1 ? "playlist" : "playlists"
            if let failed = result.errors, !failed.isEmpty {
                banners.error("Restored \(n) \(noun) to Spotify, \(failed.count) failed.")
            } else {
                banners.success("Restored \(n) \(noun) to Spotify.")
            }
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? "Please try again."
            banners.error("Restore failed. \(detail)")
        }
    }

    private func delete(_ id: UUID) async {
        deletingID = id
        defer {
            deletingID = nil
            confirmDeleteID = nil
        }
        let ok = await BackendAPI.shared.deleteSnapshot(id: id)
        guard ok else { return }
        snapshots.removeAll { $0.id == id }
        derivedProviders[id] = nil
        detailCache[id] = nil
        detailRequest = UUID()
        if expandedID == id { expandedID = nil }
    }
}

private struct BackupSnapshotReference: Hashable {
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

private struct BackupDiffSelection: Hashable, Identifiable {
    let current: BackupSnapshotReference
    let previous: BackupSnapshotReference?

    var id: UUID { current.id }
}

/// One saved occurrence of a song. The collection is part of its identity so a
/// song removed from one playlist but retained in another is still visible in a
/// comparison.
struct BackupInventoryItem: Identifiable, Equatable, Sendable {
    let uri: String
    let name: String?
    let artist: String?
    let album: String?
    let artworkURL: String?
    let collection: String
    let position: Int
    var collectionID: String? = nil

    var id: String { "\(comparisonKey)#\(position)" }

    var comparisonKey: String {
        if let collectionID, !collectionID.isEmpty {
            return "\(uri)|id:\(collectionID)"
        }
        return legacyComparisonKey
    }

    var legacyComparisonKey: String {
        let normalizedCollection = collection
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "\(uri)|\(normalizedCollection)"
    }

    var providerID: ProviderID? {
        ProviderID(rawValue: String(uri.prefix { $0 != ":" }))
    }
}

struct BackupSnapshotDifference: Equatable, Sendable {
    let added: [BackupInventoryItem]
    let removed: [BackupInventoryItem]
}

enum BackupSnapshotDiffer {
    /// Multiset comparison preserves duplicate occurrences while matching on the
    /// stable provider URI plus collection ID, falling back to legacy names.
    static func difference(
        current: [BackupInventoryItem],
        previous: [BackupInventoryItem]
    ) -> BackupSnapshotDifference {
        var buckets = Dictionary(grouping: previous.indices, by: { previous[$0].comparisonKey })
            .mapValues { Array($0.reversed()) }
        var matchedCurrent = Set<Int>()
        var matchedPrevious = Set<Int>()
        for index in current.indices {
            if let match = buckets[current[index].comparisonKey]?.popLast() {
                matchedCurrent.insert(index)
                matchedPrevious.insert(match)
            }
        }
        // Before build 46 snapshots omitted provider playlist IDs. Match those
        // legacy rows by name, but never merge two known, distinct playlists.
        var legacy = Dictionary(grouping: previous.indices.filter { !matchedPrevious.contains($0) },
                                by: { previous[$0].legacyComparisonKey })
        for index in current.indices where !matchedCurrent.contains(index) {
            let item = current[index]
            guard let candidates = legacy[item.legacyComparisonKey],
                  let offset = candidates.firstIndex(where: {
                      item.collectionID == nil || previous[$0].collectionID == nil
                  }) else { continue }
            let match = candidates[offset]
            legacy[item.legacyComparisonKey]?.remove(at: offset)
            matchedCurrent.insert(index)
            matchedPrevious.insert(match)
        }
        return BackupSnapshotDifference(
            added: current.indices.filter { !matchedCurrent.contains($0) }.map { current[$0] },
            removed: previous.indices.filter { !matchedPrevious.contains($0) }.map { previous[$0] }
        )
    }
}

struct BackupComparisonScope {
    let sharedProviders: Set<ProviderID>
    let excludedProviders: Set<ProviderID>

    init(current: [BackupInventoryItem], previous: [BackupInventoryItem]) {
        let currentProviders = Set(current.compactMap(\.providerID))
        let previousProviders = Set(previous.compactMap(\.providerID))
        sharedProviders = currentProviders.intersection(previousProviders)
        excludedProviders = currentProviders.symmetricDifference(previousProviders)
    }

    func includes(_ item: BackupInventoryItem) -> Bool {
        guard let provider = item.providerID else { return false }
        return sharedProviders.contains(provider)
    }
}

private enum BackupInventoryLoader {
    static func load(snapshotID: UUID) async throws -> [BackupInventoryItem] {
        async let playlistsFetch = BackendAPI.shared.requireSnapshotPlaylists(snapshotID: snapshotID)
        async let likedFetch = BackendAPI.shared.requireSnapshotLikedTracks(snapshotID: snapshotID)

        let playlists = try await playlistsFetch
        let playlistRows = try await loadPlaylists(playlists, maxConcurrent: 6)
        var inventory = playlistRows
            .sorted { $0.index < $1.index }
            .flatMap(\.tracks)

        let liked = try await likedFetch
        inventory.append(contentsOf: liked.enumerated().map { offset, track in
            BackupInventoryItem(
                uri: track.spotifyTrackUri,
                name: track.trackName,
                artist: track.artistName,
                album: track.albumName,
                artworkURL: track.albumArtUrl,
                collection: "Liked Songs",
                position: track.position ?? offset,
                collectionID: "liked"
            )
        })
        return inventory
    }

    private static func loadPlaylists(
        _ playlists: [SnapshotPlaylistDTO],
        maxConcurrent: Int
    ) async throws -> [(index: Int, tracks: [BackupInventoryItem])] {
        try await withThrowingTaskGroup(of: (Int, [BackupInventoryItem]).self) { group in
            var results: [(index: Int, tracks: [BackupInventoryItem])] = []
            var nextIndex = 0

            func enqueue(_ index: Int) {
                let playlist = playlists[index]
                let collection = playlist.name?.isEmpty == false
                    ? playlist.name!
                    : "Untitled playlist"
                group.addTask {
                    let tracks = try await BackendAPI.shared.requireSnapshotTracks(
                        snapshotPlaylistID: playlist.id
                    )
                    return (index, tracks.enumerated().map { offset, track in
                        BackupInventoryItem(
                            uri: track.spotifyTrackUri,
                            name: track.trackName,
                            artist: track.artistName,
                            album: track.albumName,
                            artworkURL: track.albumArtUrl,
                            collection: collection,
                            position: track.position ?? offset,
                            collectionID: playlist.spotifyPlaylistId.flatMap { $0.isEmpty ? nil : $0 }
                        )
                    })
                }
            }

            while nextIndex < min(maxConcurrent, playlists.count) {
                enqueue(nextIndex)
                nextIndex += 1
            }
            for try await result in group {
                results.append((index: result.0, tracks: result.1))
                if nextIndex < playlists.count {
                    enqueue(nextIndex)
                    nextIndex += 1
                }
            }
            return results
        }
    }
}

private struct BackupChangesView: View {
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
        let names = excludedProviders.map { ProviderCatalog.entry($0)?.label ?? $0.rawValue }
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

                VStack(spacing: 0) {
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
                    Text(ProviderCatalog.entry(provider)?.label ?? provider.rawValue)
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

/// A concrete collection inside a backup. Keeping this value small lets the
/// parent page navigate immediately; the track payload is fetched only when the
/// user asks to inspect it.
private enum BackupContentSelection: Hashable, Identifiable {
    case playlist(id: UUID, name: String?, imageURL: String?, count: Int)
    case likedSongs(snapshotID: UUID, snapshotName: String?, count: Int)

    var id: String {
        switch self {
        case .playlist(let id, _, _, _): "playlist-\(id.uuidString)"
        case .likedSongs(let id, _, _): "liked-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .playlist(_, let name, _, _):
            name?.isEmpty == false ? name! : "Untitled playlist"
        case .likedSongs:
            "Liked Songs"
        }
    }

    var backupName: String? {
        guard case .likedSongs(_, let name, _) = self else { return nil }
        return name?.isEmpty == false ? name : nil
    }

    var imageURL: URL? {
        guard case .playlist(_, _, let value, _) = self else { return nil }
        return value.flatMap(URL.init(string:))
    }

    var expectedCount: Int {
        switch self {
        case .playlist(_, _, _, let count), .likedSongs(_, _, let count): count
        }
    }
}

private struct BackupTrackPreview: Identifiable {
    let id: String
    let uri: String
    let name: String?
    let artist: String?
    let album: String?
    let artworkURL: URL?
    let durationMS: Int?
    let position: Int?

    init(_ track: SnapshotTrackDTO, fallbackPosition: Int) {
        uri = track.spotifyTrackUri
        name = track.trackName
        artist = track.artistName
        album = track.albumName
        artworkURL = track.albumArtUrl.flatMap(URL.init(string:))
        durationMS = track.durationMs
        position = track.position
        id = "\(track.spotifyTrackUri)-\(track.position ?? fallbackPosition)"
    }

    init(_ track: SnapshotLikedTrackDTO, fallbackPosition: Int) {
        uri = track.spotifyTrackUri
        name = track.trackName
        artist = track.artistName
        album = track.albumName
        artworkURL = track.albumArtUrl.flatMap(URL.init(string:))
        durationMS = track.durationMs
        position = track.position
        id = "\(track.spotifyTrackUri)-\(track.position ?? fallbackPosition)"
    }

    var providerID: ProviderID? {
        ProviderID(rawValue: String(uri.prefix { $0 != ":" }))
    }
}

/// Read-only inspection of one captured playlist (or the liked-song bucket).
/// Backups are deliberately not playable here: this surface represents the
/// immutable saved copy and keeps restore/delete actions on the parent card.
private struct BackupContentsView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let selection: BackupContentSelection

    @State private var tracks: [BackupTrackPreview] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 0) {
                    collectionSummary
                        .padding(.bottom, 16)

                    if loading {
                        ProgressView()
                            .tint(theme.palette.rose)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 44)
                    } else if failed {
                        VStack(spacing: 10) {
                            Text("Couldn’t load all saved tracks.")
                                .font(Typography.body(13))
                                .foregroundStyle(theme.palette.textSecondary)
                            Button("Try again") { Task { await loadTracks() } }
                                .font(Typography.semibold(14))
                                .foregroundStyle(theme.palette.rose)
                                .frame(minHeight: 44)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else if tracks.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                trackRow(track, number: index + 1)
                                if index < tracks.count - 1 {
                                    Divider()
                                        .overlay(theme.palette.border)
                                        .padding(.leading, 68)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(
                            theme.palette.card,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                                .stroke(theme.palette.border, lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: selection.id) { await loadTracks() }
        .refreshable { await loadTracks() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HeartableNavigationButton(kind: .back, action: dismiss.callAsFunction)
            Text(selection.title)
                .font(Typography.heading(23))
                .foregroundStyle(theme.palette.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background(theme.palette.bg)
    }

    private var collectionSummary: some View {
        HStack(spacing: 14) {
            if let imageURL = selection.imageURL ?? tracks.compactMap(\.artworkURL).first {
                CoverArt(
                    url: imageURL,
                    size: 68,
                    corner: Theme.Radius.md,
                    placeholder: "music.note.list"
                )
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(theme.palette.roseDim)
                    .frame(width: 68, height: 68)
                    .overlay {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(theme.palette.rose)
                    }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(selection.title)
                    .font(Typography.semibold(17))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(2)

                if let backupName = selection.backupName {
                    Text(backupName)
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                }

                Text(trackCountLabel)
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textMuted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trackCountLabel: String {
        let count = loading ? selection.expectedCount : tracks.count
        return "\(count) \(count == 1 ? "track" : "tracks")"
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .medium))
            Text("No tracks were captured here.")
                .font(Typography.body(13))
        }
        .foregroundStyle(theme.palette.textMuted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func trackRow(_ track: BackupTrackPreview, number: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(Typography.body(11))
                .foregroundStyle(theme.palette.textMuted)
                .frame(width: 18, alignment: .trailing)

            CoverArt(url: track.artworkURL, size: 42, corner: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name?.isEmpty == false ? track.name! : "Saved track")
                    .font(Typography.medium(13))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)

                Text(trackDetail(track))
                    .font(Typography.body(11))
                    .foregroundStyle(theme.palette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let providerID = track.providerID {
                ProviderBadge(id: providerID, size: 18)
            }

            if let duration = durationLabel(track.durationMS) {
                Text(duration)
                    .font(Typography.body(10))
                    .monospacedDigit()
                    .foregroundStyle(theme.palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .accessibilityElement(children: .combine)
    }

    private func trackDetail(_ track: BackupTrackPreview) -> String {
        [track.artist, track.album]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    private func durationLabel(_ milliseconds: Int?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        let seconds = milliseconds / 1_000
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func loadTracks() async {
        loading = true
        failed = false
        defer { loading = false }

        do {
            let loaded: [BackupTrackPreview]
            switch selection {
            case .playlist(let id, _, _, _):
                loaded = try await BackendAPI.shared.requireSnapshotTracks(snapshotPlaylistID: id)
                    .enumerated().map { BackupTrackPreview($0.element, fallbackPosition: $0.offset) }
            case .likedSongs(let snapshotID, _, _):
                loaded = try await BackendAPI.shared.requireSnapshotLikedTracks(snapshotID: snapshotID)
                    .enumerated().map { BackupTrackPreview($0.element, fallbackPosition: $0.offset) }
            }
            guard loaded.count == selection.expectedCount else { failed = true; return }
            tracks = loaded
        } catch {
            failed = true
        }
    }
}

private struct BackupActionsSheet: View {
    @Environment(ThemeStore.self) private var theme

    let snapshot: LibrarySnapshotDTO
    let exportName: String
    let isRestoring: Bool
    let onClose: () -> Void
    let onRename: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HeartableDrawer { content }
            .accessibilityAction(.escape, onClose)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup actions")
                        .font(Typography.heading(23))
                        .foregroundStyle(theme.palette.text)
                    Text(snapshot.name?.isEmpty == false ? snapshot.name! : "Heartable backup")
                        .font(Typography.body(13))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                Spacer(minLength: 8)
            }

            VStack(spacing: 9) {
                Button(action: onRename) {
                    actionRow(icon: "pencil", title: "Rename", destructive: false)
                }
                .buttonStyle(.plain)

                ShareLink(
                    item: CSVDocument(snapshot: snapshot),
                    preview: SharePreview("\(exportName).csv")
                ) {
                    actionRow(
                        icon: "square.and.arrow.up",
                        title: "Export CSV",
                        destructive: false
                    )
                }
                .buttonStyle(.plain)

                Button(action: onRestore) {
                    actionRow(
                        icon: "arrow.uturn.backward",
                        title: isRestoring ? "Restoring…" : "Restore to Spotify",
                        destructive: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)

                Button(role: .destructive, action: onDelete) {
                    actionRow(
                        icon: "trash.fill",
                        title: "Delete backup",
                        destructive: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(theme.palette.bg.ignoresSafeArea())
        .accessibilityAction(.escape, onClose)
    }

    private func actionRow(
        icon: String,
        title: String,
        destructive: Bool
    ) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    destructive
                        ? theme.palette.danger.opacity(0.12)
                        : theme.palette.roseDim
                )
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            destructive
                                ? theme.palette.danger
                                : theme.palette.rose
                        )
                }
            Text(title)
                .font(Typography.semibold(14))
                .foregroundStyle(
                    destructive ? theme.palette.danger : theme.palette.text
                )
            Spacer()
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(theme.palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(theme.palette.border, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}

/// How often Heartable should auto-capture, persisted per Heartable account.
private enum BackupFrequency: String, CaseIterable, Identifiable {
    case manual, daily, weekly, monthly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .manual: "Manual"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}

// MARK: - CSV export document

/// A `Transferable` CSV built from a snapshot's tracks. Fetched lazily when the
/// share sheet asks for the data. Optional artwork columns survive re-import.
///
/// The export writes every playlist's tracks, then appends liked songs with an
/// empty `playlist` column. That empty column is the documented liked-song marker
/// the importer reads (rows with no playlist → `snapshot_liked_tracks`), so an
/// exported CSV round-trips back into liked songs on re-import.
struct CSVDocument: Transferable {
    let snapshot: LibrarySnapshotDTO

    /// One CSV line: the source playlist name plus the track fields.
    struct Row: Sendable {
        let playlist: String
        let name: String?
        let artist: String?
        let album: String?
        let uri: String
        var albumArtURL: String? = nil
        var playlistImageURL: String? = nil
        var durationMS: Int? = nil
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { doc in
            let rows = await Self.rows(for: doc.snapshot.id)
            return Data(Self.csv(from: rows).utf8)
        }
        .suggestedFileName { doc in
            let base = doc.snapshot.name?.isEmpty == false ? doc.snapshot.name! : "snapshot"
            let safe = base.map { $0.isLetter || $0.isNumber ? $0 : "-" }
            return "heartable-backup-" + String(safe) + ".csv"
        }
    }

    /// Gather every track across the snapshot's playlists, then append liked songs
    /// (empty `playlist` column so they re-import as liked, not as a playlist).
    static func rows(for snapshotID: UUID) async -> [Row] {
        async let playlistsFetch = BackendAPI.shared.fetchSnapshotPlaylists(snapshotID: snapshotID)
        async let likedFetch = BackendAPI.shared.fetchSnapshotLikedTracks(snapshotID: snapshotID)
        let playlists = await playlistsFetch
        let playlistRows = await fetchPlaylistRows(playlists, maxConcurrent: 6)
        var rows: [Row] = []
        for (index, label, tracks) in playlistRows.sorted(by: { $0.0 < $1.0 }) {
            for t in tracks {
                rows.append(Row(playlist: label, name: t.trackName, artist: t.artistName,
                                album: t.albumName, uri: t.spotifyTrackUri,
                                albumArtURL: t.albumArtUrl, playlistImageURL: playlists[index].imageUrl,
                                durationMS: t.durationMs))
            }
        }
        // Always include liked songs with an empty playlist column (the importer's
        // liked-song marker), so full snapshots export every track and round-trip.
        let liked = await likedFetch
        for t in liked {
            rows.append(Row(playlist: "", name: t.trackName, artist: t.artistName,
                            album: t.albumName, uri: t.spotifyTrackUri,
                            albumArtURL: t.albumArtUrl, durationMS: t.durationMs))
        }
        return rows
    }

    /// Fetch playlist contents with bounded concurrency while retaining the
    /// snapshot's playlist order in the exported document.
    private static func fetchPlaylistRows(
        _ playlists: [SnapshotPlaylistDTO],
        maxConcurrent: Int
    ) async -> [(Int, String, [SnapshotTrackDTO])] {
        await withTaskGroup(of: (Int, String, [SnapshotTrackDTO]).self) { group in
            var results: [(Int, String, [SnapshotTrackDTO])] = []
            var next = 0

            func enqueue(_ index: Int) {
                let playlist = playlists[index]
                let label = playlist.name?.isEmpty == false
                    ? playlist.name!
                    : "Untitled playlist"
                group.addTask {
                    let tracks = await BackendAPI.shared.fetchSnapshotTracks(
                        snapshotPlaylistID: playlist.id
                    )
                    return (index, label, tracks)
                }
            }

            while next < min(maxConcurrent, playlists.count) {
                enqueue(next)
                next += 1
            }
            for await result in group {
                results.append(result)
                if next < playlists.count {
                    enqueue(next)
                    next += 1
                }
            }
            return results
        }
    }

    static func csv(from rows: [Row]) -> String {
        var lines = ["playlist,name,artist,album,uri,album_art_url,playlist_image_url,duration_ms"]
        for r in rows {
            lines.append([
                escape(r.playlist),
                escape(r.name),
                escape(r.artist),
                escape(r.album),
                escape(r.uri),
                escape(r.albumArtURL),
                escape(r.playlistImageURL),
                r.durationMS.map(String.init) ?? "",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        // Quote if the field contains a comma, quote, or any newline (CR or LF),
        // doubling embedded quotes per RFC 4180.
        if value.contains("\"") || value.contains(",")
            || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

/// Compact wrapping layout for service badges. It preserves each chip's natural
/// width and adds rows only when the available width is genuinely exhausted.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(subviews: subviews, width: proposal.width ?? .greatestFiniteMagnitude).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (index, point) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, min(width, x - spacing))
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), origins)
    }
}
