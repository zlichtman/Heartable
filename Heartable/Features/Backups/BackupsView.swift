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
    @State private var undatedRows: [ImportedRow] = []
    @State private var importOwner: UUID?
    @State private var showingImportDate = false
    @State private var originalImportDate = Date()

    // Per-snapshot transient state.
    @State private var expandedID: UUID?
    @State private var playlists: [SnapshotPlaylistDTO] = []
    @State private var likedCount = 0
    @State private var detailLoading = false
    @State private var detailFailed = false
    @State private var detailRequest = UUID()
    @State private var detailCache: [UUID: BackupDetail] = [:]
    @State private var reloadRequest = UUID()
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
        .onAppear { MainThreadStallMonitor.note("open Backups") }
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
            reloadRequest = UUID()
            selectedContent = nil
            selectedDiff = nil
        }
        .sheet(isPresented: $showingImportDate, onDismiss: { undatedRows = [] }) {
            HeartableDrawer {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Original backup date").font(Typography.heading(23)).foregroundStyle(theme.palette.text)
                    Text("This older CSV has no creation date. Choose when the backup was made.")
                        .font(Typography.body(14)).foregroundStyle(theme.palette.textSecondary)
                    DatePicker("Created", selection: $originalImportDate, in: ...Date())
                        .tint(theme.palette.rose)
                    Button("Import backup") {
                        let rows = undatedRows
                        let owner = importOwner
                        let date = originalImportDate
                        showingImportDate = false
                        Task {
                            guard owner == AccountSessionStore.currentOwnerID else { return }
                            await saveImportedRows(rows, createdAt: date)
                        }
                    }
                    .font(Typography.semibold(15)).foregroundStyle(theme.palette.text)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(theme.palette.roseDim, in: Capsule())
                }.padding(20)
            }
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
                    Image(systemName: !loaded || backupInProgress
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
                    if backupInProgress {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "externaldrive.fill.badge.plus")
                    }
                    Text(backupInProgress ? "Saving backup…" : "Back Up Now")
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
        if backupInProgress { return "Saving your backup…" }
        if !loaded { return "Checking your backups…" }
        return snapshots.isEmpty ? "Create your first backup" : "Your library is protected"
    }

    private var overviewSubtitle: String {
        if backupInProgress { return "Your playlists and songs will appear here when saving finishes." }
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

    private var backupInProgress: Bool { capturing || backupScheduler.isRunning }

    private var captureDisabled: Bool { backupInProgress || selectedProviderIDs.isEmpty }

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
                        Text(ProviderCatalog.label(for: id))
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
                Button("Couldn’t load backup. Tap to retry.") {
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
        let request = UUID()
        reloadRequest = request
        let owner = AccountSessionStore.currentOwnerID
        let fetched = await BackendAPI.shared.fetchSnapshots()
        guard reloadRequest == request, AccountSessionStore.currentOwnerID == owner else { return }
        snapshots = fetched
        // A completion notification or pull-to-refresh must replace any detail
        // read while an older client's capture was still uploading.
        detailCache = [:]
        detailRequest = UUID()
        if let expandedID, let snapshot = fetched.first(where: { $0.id == expandedID }) {
            await loadDetail(snapshot)
        } else {
            expandedID = nil
        }
        guard reloadRequest == request, AccountSessionStore.currentOwnerID == owner else { return }
        await deriveProviderSets(for: fetched, request: request, owner: owner)
    }

    /// Resolve each snapshot's true service set from its captured contents, so the
    /// label reflects only what actually landed in that snapshot (not the set the
    /// user had selected at capture time). The backend helper resolves the whole
    /// page with a fixed three-query batch.
    private func deriveProviderSets(for snaps: [LibrarySnapshotDTO], request: UUID, owner: UUID?) async {
        let ids = snaps.map(\.id)
        let resolved = await BackendAPI.shared.snapshotProviderIDs(snapshotIDs: ids)
        guard reloadRequest == request, AccountSessionStore.currentOwnerID == owner else { return }
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
            // Surface the columns actually found so a header mismatch ("Track URI"
            // vs "uri", a JSON file, etc.) is obvious.
            let cols = CSVImportParser.headerColumns(text)
            let detail = cols.isEmpty
                ? "The file looked empty or wasn’t a CSV."
                : "Couldn’t find a track-URI column. Columns found: \(cols.joined(separator: ", "))."
            banners.error("Import failed. \(detail)")
            return
        }

        do {
            if let date = try CSVImportParser.snapshotDate(text) {
                await saveImportedRows(rows, createdAt: date)
            } else {
                undatedRows = rows
                importOwner = AccountSessionStore.currentOwnerID
                originalImportDate = Date()
                showingImportDate = true
            }
        } catch {
            banners.error((error as? LocalizedError)?.errorDescription ?? "Invalid backup date.")
        }
    }

    private func saveImportedRows(_ rows: [ImportedRow], createdAt: Date) async {
        guard let owner = AccountSessionStore.currentOwnerID else { return }
        importing = true
        defer { importing = false }
        let name = BackupName.timestamp(createdAt)
        do {
            let result = try await backupScheduler.performManualCapture {
                try await BackendAPI.shared.importSnapshotFromCSV(name: name, rows: rows, createdAt: createdAt, expectedUserID: owner)
            }
            await reload()
            banners.success("Imported \(result.playlistCount) playlists, \(result.trackCount) tracks, \(result.likedCount) liked.")
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
        await loadDetail(snap)
    }

    private func loadDetail(_ snap: LibrarySnapshotDTO) async {
        let request = UUID()
        detailRequest = request
        let owner = AccountSessionStore.currentOwnerID
        detailFailed = false
        if let cached = detailCache[snap.id], cached.matches(snap) {
            playlists = cached.playlists
            likedCount = cached.likedCount
            detailLoading = false
            expandedID = snap.id
            return
        }
        detailLoading = true
        expandedID = snap.id
        playlists = []
        likedCount = 0
        do {
            async let pls = BackendAPI.shared.requireSnapshotPlaylists(snapshotID: snap.id)
            async let liked = BackendAPI.shared.requireSnapshotLikedTracks(snapshotID: snap.id)
            let (loadedPls, loadedLiked) = try await (pls, liked)
            guard detailRequest == request, AccountSessionStore.currentOwnerID == owner else { return }
            let detail = BackupDetail(playlists: loadedPls, likedCount: loadedLiked.count)
            guard detail.matches(snap) else {
                throw BackendError.message("This backup’s contents are not fully available yet.")
            }
            detailCache[snap.id] = detail
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
