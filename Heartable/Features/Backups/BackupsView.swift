import SwiftUI
import UniformTypeIdentifiers

/// Backups — a focused protection dashboard: create a snapshot from selected
/// connected services, choose an automatic cadence, import/export CSV, and browse
/// restorable history. Restoring currently targets Spotify; capture supports every
/// live provider represented by the local snapshot importer.
struct BackupsView: View {
    private enum PendingBackupAction {
        case restore(UUID)
        case delete(UUID)
    }
    @Environment(ThemeStore.self) private var theme
    @Environment(ProvidersStore.self) private var providers
    @Environment(BannerCenter.self) private var banners

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
    @State private var restoringID: UUID?
    @State private var deletingID: UUID?

    // Confirmation alerts (carry the target snapshot id).
    @State private var confirmDeleteID: UUID?
    @State private var confirmRestoreID: UUID?
    @State private var actionSnapshot: LibrarySnapshotDTO?
    @State private var pendingBackupAction: PendingBackupAction?

    // Scheduled capture preference, consumed by BackupScheduler on launch/foreground.
    @State private var frequency = BackupFrequency.manual.rawValue

    // Bumped on each service-chip tap so the view re-reads the persisted selection.
    @State private var selectionTick = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Backups")
                .font(Typography.heading(32))
                .foregroundStyle(theme.palette.text)
            Text("Protect your library and restore it when you need it.")
                .font(Typography.body(14))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        } else {
            ForEach(snapshots) { snap in
                snapshotCard(snap)
            }
        }
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
                expandedDetail
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
    private var expandedDetail: some View {
        Divider().overlay(theme.palette.border)

        VStack(alignment: .leading, spacing: 10) {
            if likedCount > 0 {
                Label("\(likedCount) liked songs", systemImage: "heart.fill")
                    .font(Typography.medium(12))
                    .foregroundStyle(theme.palette.textSecondary)
            }

            if playlists.isEmpty {
                Text("No playlists in this snapshot.")
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textMuted)
            } else {
                ForEach(playlists) { pl in
                    HStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.palette.textMuted)
                            .frame(width: 16)
                        Text(pl.name?.isEmpty == false ? pl.name! : "Untitled playlist")
                            .font(Typography.medium(13))
                            .foregroundStyle(theme.palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(pl.trackCount ?? 0)")
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textMuted)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
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
            let result = try await BackendAPI.shared.captureSnapshot(providerIDs: ids)
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

        let name = url.deletingPathExtension().lastPathComponent
        do {
            let result = try await BackendAPI.shared.importSnapshotFromCSV(name: name, rows: rows)
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
            return
        }
        expandedID = snap.id
        playlists = []
        likedCount = 0
        async let pls = BackendAPI.shared.fetchSnapshotPlaylists(snapshotID: snap.id)
        async let liked = BackendAPI.shared.fetchSnapshotLikedTracks(snapshotID: snap.id)
        let (loadedPls, loadedLiked) = await (pls, liked)
        guard expandedID == snap.id else { return }
        playlists = loadedPls
        likedCount = loadedLiked.count
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
        if expandedID == id { expandedID = nil }
    }
}

private struct BackupActionsSheet: View {
    @Environment(ThemeStore.self) private var theme

    let snapshot: LibrarySnapshotDTO
    let exportName: String
    let isRestoring: Bool
    let onClose: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
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
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(theme.palette.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            VStack(spacing: 9) {
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
        .presentationSizing(.fitted)
        .presentationBackground(theme.palette.bg)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
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
/// share sheet asks for the data. Columns: playlist,name,artist,album,uri.
///
/// The export writes every playlist's tracks, then appends liked songs with an
/// empty `playlist` column. That empty column is the documented liked-song marker
/// the importer reads (rows with no playlist → `snapshot_liked_tracks`), so an
/// exported CSV round-trips back into liked songs on re-import.
private struct CSVDocument: Transferable {
    let snapshot: LibrarySnapshotDTO

    /// One CSV line: the source playlist name plus the track fields.
    struct Row: Sendable {
        let playlist: String
        let name: String?
        let artist: String?
        let album: String?
        let uri: String
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
        for (_, label, tracks) in playlistRows.sorted(by: { $0.0 < $1.0 }) {
            for t in tracks {
                rows.append(Row(playlist: label, name: t.trackName, artist: t.artistName,
                                album: t.albumName, uri: t.spotifyTrackUri))
            }
        }
        // Always include liked songs with an empty playlist column (the importer's
        // liked-song marker), so full snapshots export every track and round-trip.
        let liked = await likedFetch
        for t in liked {
            rows.append(Row(playlist: "", name: t.trackName, artist: t.artistName,
                            album: t.albumName, uri: t.spotifyTrackUri))
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
        var lines = ["playlist,name,artist,album,uri"]
        for r in rows {
            lines.append([
                escape(r.playlist),
                escape(r.name),
                escape(r.artist),
                escape(r.album),
                escape(r.uri),
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
