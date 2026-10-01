import SwiftUI
import PhotosUI
import UIKit

/// Mixtape editor — cover + editable title/description, a reorderable track list
/// (swipe-to-delete + drag reorder via EditButton), an "Add tracks" search sheet
/// over connected providers, and a "Share" sheet that toggles friend access.
/// When the mixtape isn't mine the editing affordances are hidden and the list
/// is read-only. Ported from the RN MixtapeEditorScreen.
struct MixtapeEditorView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(PlaybackPrefsStore.self) private var prefs
    @Environment(BannerCenter.self) private var banners
    @Environment(\.dismiss) private var dismiss

    let mixtapeID: UUID
    var recipientName: String? = nil
    /// Debug screenshots hand the editor its content instead of a backend read.
    var fixture: MixtapeDetailDTO? = nil

    @State private var mixtape: MixtapeDTO?
    @State private var tracks: [MixtapeTrackDTO] = []
    @State private var title = ""
    @State private var description = ""

    @State private var showSearch = false
    @State private var showShare = false
    @State private var loaded = false

    @State private var coverItem: PhotosPickerItem?
    @State private var uploadingCover = false
    @State private var editMode: EditMode = .inactive
    @State private var noteTrack: MixtapeTrackDTO?
    @State private var sending = false
    @State private var metadataSaveTask: Task<Bool, Never>?
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleted = false
    @State private var changingTracks = false
    @State private var savingMetadata = false
    @State private var metadataFailed = false

    private var editable: Bool { !deleted && (mixtape?.mine ?? false) }
    private var metadataDirty: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? "Untitled mixtape" : trimmed) != mixtape?.title
            || description != (mixtape?.description ?? "")
    }

    var body: some View {
        ZStack {
            theme.palette.bg.ignoresSafeArea()
            if mixtape == nil && loaded {
                notFound
            } else {
                list
            }
        }
        .environment(\.editMode, $editMode)
        .disabled(sending || deleting || changingTracks)
        .navigationTitle(title.isEmpty ? "Mixtape" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editable {
                ToolbarItem(placement: .topBarTrailing) {
                    if editMode == .active {
                        HeartableToolbarAction(title: "Done") {
                            withAnimation { editMode = .inactive }
                        }
                    } else if mixtape?.recipientId != nil, mixtape?.sentAt == nil {
                        HeartableToolbarAction(title: "Send") { Task { await sendGift() } }
                            .disabled(uploadingCover || tracks.isEmpty)
                    } else {
                        Button {
                            Task { if await saveMeta() { showShare = true } }
                        } label: {
                            Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                        }
                        .disabled(uploadingCover || tracks.isEmpty)
                        .accessibilityLabel("Share mixtape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            withAnimation { editMode = editMode == .active ? .inactive : .active }
                        } label: {
                            Label(editMode == .active ? "Finish reordering" : "Reorder songs", systemImage: "arrow.up.arrow.down")
                        }
                        if mixtape?.recipientId != nil, mixtape?.sentAt == nil {
                            Button {
                                Task { if await saveMeta() { showShare = true } }
                            } label: { Label("Share link", systemImage: "link") }
                                .disabled(uploadingCover || tracks.isEmpty)
                        }
                        if mixtape?.coverUrl?.isEmpty == false {
                            Button(role: .destructive) { Task { await removeCover() } } label: {
                                Label("Remove cover", systemImage: "photo.badge.minus")
                            }.disabled(uploadingCover)
                        }
                        Divider()
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label("Delete mixtape", systemImage: "trash")
                        }.disabled(uploadingCover || changingTracks)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Mixtape options")
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            AddTracksSheet(mixtapeID: mixtapeID, existingURIs: Set(tracks.map(\.trackUri))) { await load(preserveEdits: true) }
        }
        .sheet(isPresented: $showShare) {
            MixtapeLinkSheet(mixtapeID: mixtapeID)
        }
        .sheet(item: $noteTrack) { track in
            MixtapeSongNoteSheet(mixtapeID: mixtapeID, track: track) { await load(preserveEdits: true) }
        }
        .sheet(isPresented: $confirmingDelete) {
            HeartableDestructiveConfirmation(
                icon: "trash", title: "Delete mixtape?",
                message: "This removes the mixtape and revokes its shared link. This can’t be undone.",
                confirmTitle: "Delete mixtape", cancelTitle: "Keep mixtape", isBusy: deleting,
                onCancel: { confirmingDelete = false },
                onConfirm: { Task { await deleteMixtape() } }
            )
        }
        .task { await load() }
        .task(id: [title, description]) {
            guard editable, title != (mixtape?.title ?? "") || description != (mixtape?.description ?? "") else { return }
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            _ = await saveMeta()
        }
        .onDisappear { Task { _ = await saveMeta() } }
    }

    // MARK: List

    private var list: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 20, trailing: 0))
            }

            Section {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, t in trackRow(t, number: index + 1) }
                    .onDelete(perform: deleteTracks)
                    .onMove(perform: moveTracks)

                if editable {
                    Button { showSearch = true } label: {
                        Label("Add songs", systemImage: "plus.circle")
                            .font(Typography.semibold(15))
                            .foregroundStyle(theme.palette.rose)
                            .frame(minHeight: 44)
                    }
                    .listRowBackground(theme.palette.bg)
                }
            } footer: {
                if editable, !tracks.isEmpty, !tracks.contains(where: hasNote) {
                    Text("Swipe right on a song to add a note or a photo.")
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textMuted)
                        .padding(.top, 6)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.palette.bg)
    }

    /// "For Ava · Feb 14": who it's for and when it was given, the way a gift is labeled.
    private var dedication: String? {
        guard mixtape?.recipientId != nil else { return nil }
        let name = editable ? (recipientName ?? "your friend") : "you"
        guard let sent = mixtape?.sentAt.flatMap(Self.parseDate) else { return editable ? "For \(name) · Draft" : "For \(name)" }
        return "For \(name) · \(sent.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private var runtime: String {
        let minutes = tracks.reduce(0) { $0 + ($1.durationMs ?? 0) } / 60_000
        let songs = "\(tracks.count) song\(tracks.count == 1 ? "" : "s")"
        return minutes > 0 ? "\(songs) · \(minutes) min" : songs
    }

    /// Only a save that needs attention is shown; a saved mixtape says nothing.
    private var saveStatus: String? {
        if metadataFailed { return "Changes not saved" }
        if savingMetadata { return "Saving…" }
        return nil
    }

    private var header: some View {
        VStack(spacing: 20) {
            cover
            VStack(spacing: 10) {
                if let dedication {
                    Text(dedication.uppercased())
                        .font(Typography.semibold(11))
                        .tracking(1.6)
                        .foregroundStyle(theme.palette.rose)
                }
                if editable {
                    TextField("Mixtape title", text: $title)
                        .font(Typography.heading(30))
                        .foregroundStyle(theme.palette.text)
                        .multilineTextAlignment(.center)
                        .onSubmit { Task { _ = await saveMeta() } }
                    TextField("Write them a dedication", text: $description, axis: .vertical)
                        .font(Typography.body(15))
                        .foregroundStyle(theme.palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .onSubmit { Task { _ = await saveMeta() } }
                } else {
                    Text(title.isEmpty ? "Untitled mixtape" : title)
                        .font(Typography.heading(30))
                        .foregroundStyle(theme.palette.text)
                        .multilineTextAlignment(.center)
                    if !description.isEmpty {
                        Text(description)
                            .font(Typography.body(15))
                            .foregroundStyle(theme.palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                if editable, let saveStatus {
                    Text(saveStatus)
                        .font(Typography.medium(12))
                        .foregroundStyle(metadataFailed ? theme.palette.danger : theme.palette.textMuted)
                    if metadataFailed {
                        Button("Retry save") { Task { _ = await saveMeta() } }
                            .foregroundStyle(theme.palette.rose).frame(minHeight: 44)
                    }
                }
            }
            .padding(.horizontal, 28)

            if !tracks.isEmpty {
                VStack(spacing: 10) {
                    Button {
                        Task { await player.play(tracks: tracks.map(unified), startingAt: nil, mode: prefs.mode) }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(Typography.semibold(15))
                            .foregroundStyle(theme.palette.bg)
                            .padding(.horizontal, 30)
                            .frame(minHeight: 44)
                            .background(theme.palette.rose, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Text(runtime)
                        .font(Typography.medium(12))
                        .foregroundStyle(theme.palette.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var cover: some View {
        if editable {
            let coverURLString = mixtape?.coverUrl
            let isUploading = uploadingCover

            // Editable mixtapes: tap the cover to pick + upload a new image.
            PhotosPicker(selection: $coverItem, matching: .images) {
                MixtapeCoverPickerLabel(
                    urlString: coverURLString,
                    isUploading: isUploading
                )
            }
            .buttonStyle(.plain)
            .disabled(uploadingCover)
            .onChange(of: coverItem) { _, item in
                guard let item else { return }
                Task { await uploadCover(item) }
            }
        } else {
            // Shared (read-only) mixtapes keep the plain cover.
            coverImage
        }
    }

    private var coverImage: some View {
        MixtapeCoverArtwork(urlString: mixtape?.coverUrl)
    }

    private var notFound: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 30))
                .foregroundStyle(theme.palette.textMuted)
            Text("Mixtape not found.")
                .font(Typography.body(14))
                .foregroundStyle(theme.palette.textSecondary)
            Button("Back") { dismiss() }
                .font(Typography.semibold(14))
                .foregroundStyle(theme.palette.rose)
        }
        .padding(28)
    }

    // MARK: Data

    private func load(preserveEdits: Bool = false) async {
        let detail: MixtapeDetailDTO?
        if let fixture {
            detail = fixture
        } else {
            detail = await BackendAPI.shared.getMixtape(id: mixtapeID)
        }
        loaded = true
        guard let detail else { return }
        mixtape = detail.mixtape
        tracks = detail.tracks.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        if !preserveEdits {
            title = detail.mixtape.title ?? ""
            description = detail.mixtape.description ?? ""
        }
    }

    private func saveMeta() async -> Bool {
        guard editable, !deleting, let owner = mixtape?.owner,
              AccountSessionStore.currentOwnerID == owner else { return false }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedTitle = t.isEmpty ? "Untitled mixtape" : t
        let savedDescription = description
        let previous = metadataSaveTask
        let task = Task { @MainActor in
            // Serialize saves even when a debounce task is cancelled by more
            // typing. The last edit cannot be overwritten by an older request.
            if let previous { _ = await previous.value }
            guard !deleted, AccountSessionStore.currentOwnerID == owner else { return false }
            savingMetadata = true
            defer { savingMetadata = false }
            do {
                try await BackendAPI.shared.updateMixtape(
                    id: mixtapeID,
                    title: savedTitle,
                    description: savedDescription
                )
                mixtape?.title = savedTitle
                mixtape?.description = savedDescription
                metadataFailed = false
                return true
            } catch {
                metadataFailed = true
                banners.error("Couldn’t save the mixtape details. Try again.")
                return false
            }
        }
        metadataSaveTask = task
        return await task.value
    }

    private func deleteMixtape() async {
        guard editable, !deleting, !uploadingCover, !changingTracks else { return }
        deleting = true
        defer { deleting = false }
        // Drain queued metadata saves before deleting; never autosave on exit.
        if let metadataSaveTask { _ = await metadataSaveTask.value }
        do {
            try await BackendAPI.shared.deleteMixtape(id: mixtapeID)
            deleted = true
            confirmingDelete = false
            banners.success("Mixtape deleted")
            dismiss()
        } catch { banners.error("Couldn’t delete the mixtape. Try again.") }
    }

    private func removeCover() async {
        guard editable, !uploadingCover else { return }
        uploadingCover = true
        defer { uploadingCover = false }
        do {
            try await BackendAPI.shared.updateMixtape(id: mixtapeID, coverUrl: .some(""))
            mixtape?.coverUrl = nil
            coverItem = nil
        } catch { banners.error("Couldn’t remove the cover. Try again.") }
    }

    private func sendGift() async {
        guard !sending, let tape = mixtape, let recipient = tape.recipientId, !tracks.isEmpty else { return }
        sending = true
        defer { sending = false }
        guard await saveMeta() else { return }
        do {
            try await BackendAPI.shared.sendMixtapeGift(id: mixtapeID, friendID: recipient, expectedOwner: tape.owner)
            await load(preserveEdits: true)
            banners.success("Mixtape sent to \(recipientName ?? "your friend")")
        } catch { banners.error("Couldn’t send your mixtape. Your draft is saved; try again.") }
    }

    private func uploadCover(_ item: PhotosPickerItem) async {
        guard editable else { return }
        uploadingCover = true
        defer { uploadingCover = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let jpeg = await ImageDownscale.jpegInBackground(from: data) else { throw ProviderError("Invalid photo") }
            let url = try await BackendAPI.shared.uploadMixtapeImage(mixtapeID: mixtapeID, jpeg)
            try await BackendAPI.shared.updateMixtape(id: mixtapeID, coverUrl: .some(url))
            // Resolve the private reference for immediate display without
            // replacing other unsaved editor state.
            mixtape?.coverUrl = await BackendAPI.shared.mixtapeMediaDisplayURL(url)
        } catch {
            banners.error("Couldn’t save the mixtape cover. Try again.")
        }
    }

    @ViewBuilder
    private func hasNote(_ t: MixtapeTrackDTO) -> Bool {
        t.note?.isEmpty == false || t.noteImageUrl?.isEmpty == false
    }

    private func trackRow(_ t: MixtapeTrackDTO, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            UnifiedTrackRow(track: unified(t), rank: number) {
                Task { await player.play(tracks: tracks.map(unified),
                                         startingAt: tracks.firstIndex { $0.id == t.id },
                                         mode: prefs.mode) }
            }
            if hasNote(t) {
                HStack(alignment: .top, spacing: 12) {
                    Capsule().fill(theme.palette.rose).frame(width: 2)
                    VStack(alignment: .leading, spacing: 10) {
                        if let note = t.note, !note.isEmpty {
                            Text(note)
                                .font(Typography.body(15))
                                .foregroundStyle(theme.palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let image = t.noteImageUrl, !image.isEmpty {
                            ArtworkThumb(urlString: image, size: 132, corner: 14)
                        }
                    }
                }
                .padding(.leading, 6)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
                .onTapGesture { if editable { noteTrack = t } }
                .accessibilityElement(children: .combine)
                .accessibilityHint(editable ? "Edit note" : "")
            }
        }
        .listRowBackground(theme.palette.bg)
        .listRowSeparatorTint(theme.palette.border)
        .swipeActions(edge: .leading) {
            if editable {
                Button { noteTrack = t } label: {
                    Label(hasNote(t) ? "Edit note" : "Add note", systemImage: "square.and.pencil")
                }
                .tint(theme.palette.rose)
            }
        }
        .contextMenu {
            if editable {
                Button { noteTrack = t } label: {
                    Label(hasNote(t) ? "Edit note or photo" : "Add note or photo", systemImage: "square.and.pencil")
                }
            }
        }
    }

    private func deleteTracks(_ offsets: IndexSet) {
        guard editable, !changingTracks else { return }
        let removed = offsets.map { tracks[$0] }
        changingTracks = true
        Task {
            defer { changingTracks = false }
            do {
                for t in removed { try await BackendAPI.shared.deleteMixtapeTrack(id: t.id) }
            } catch { banners.error("Some tracks couldn’t be removed. Check the refreshed list and try again.") }
            await load(preserveEdits: true)
        }
    }

    private func moveTracks(_ offsets: IndexSet, _ destination: Int) {
        guard editable, !changingTracks else { return }
        changingTracks = true
        tracks.move(fromOffsets: offsets, toOffset: destination)
        let ordered = tracks.enumerated().map { (id: $0.element.id, position: $0.offset) }
        Task {
            defer { changingTracks = false }
            do { try await BackendAPI.shared.reorderMixtapeTracks(ordered) }
            catch {
                banners.error("The order wasn’t fully saved. Check the refreshed list and try again.")
                await load(preserveEdits: true)
            }
        }
    }

    // MARK: Track mapping

    /// Build a `UnifiedTrack` from a stored mixtape-track row so the standard
    /// row + player can consume it. The provider id is recovered from the uri
    /// prefix (e.g. "spotify:track:xyz" -> .spotify), defaulting to Spotify.
    private func unified(_ t: MixtapeTrackDTO) -> UnifiedTrack {
        let providerID = ProviderID(rawValue: String(t.trackUri.split(separator: ":").first ?? "spotify")) ?? .spotify
        let providerTrackID = String(t.trackUri.split(separator: ":").last ?? "")
        let artistName = t.artist ?? ""
        return UnifiedTrack(
            key: t.trackUri,
            providerID: providerID,
            providerTrackID: providerTrackID,
            uri: t.trackUri,
            name: t.trackName ?? "",
            artists: [UnifiedArtist(id: artistName, name: artistName)],
            album: nil,
            albumArt: URL(string: t.albumArt ?? ""),
            durationMs: t.durationMs ?? 0
        )
    }
}

private struct MixtapeCoverPickerLabel: View {
    @Environment(ThemeStore.self) private var theme

    let urlString: String?
    let isUploading: Bool

    var body: some View {
        MixtapeCoverArtwork(urlString: urlString)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.35), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(12)
                    .accessibilityLabel("Change cover")
            }
            .overlay {
                if isUploading {
                    ProgressView().tint(.white)
                }
            }
            .opacity(isUploading ? 0.6 : 1)
    }
}

private struct MixtapeCoverArtwork: View {
    @Environment(ThemeStore.self) private var theme

    let urlString: String?

    var body: some View {
        Group {
            if let image = demoArtwork {
                image.resizable().scaledToFill()
            } else if let urlString, let url = URL(string: urlString) {
                CachedArtworkImage(url: url) { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: 264, height: 264)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 14)
    }

    private var demoArtwork: Image? {
        #if DEBUG
        if urlString == "heartable-fixture://mixtape-scenery" { return Image("MixtapeDemoScenery") }
        #endif
        return nil
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [theme.palette.grad1, theme.palette.grad3],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "heart.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - Add tracks sheet

private struct AddTracksSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(BannerCenter.self) private var banners
    @Environment(LibrarySessionStore.self) private var librarySession
    @Environment(\.dismiss) private var dismiss

    let mixtapeID: UUID
    let existingURIs: Set<String>
    let onAdded: () async -> Void
    @State private var query = ""
    @State private var hits: [UnifiedTrack] = []
    @State private var searching = false
    @State private var adding = false
    @State private var added: Set<String> = []
    @State private var selection: [UnifiedTrack] = []
    @State private var insertionIDs: [String: UUID] = [:]

    private var visible: [UnifiedTrack] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cached = librarySession.master.tracks.compactMap { $0.sources.first }
            .filter { track in
                track.providerID != .wsum && (q.isEmpty ||
                    "\(track.name) \(track.artistNames)".localizedStandardContains(q))
            }
        var seen: Set<String> = []
        return Array((cached + hits).filter { seen.insert($0.uri).inserted }.prefix(200))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if searching {
                        Text("Searching services…").font(Typography.body(13))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    if visible.isEmpty {
                        Text(query.isEmpty ? "Search for songs to start your mixtape." :
                             searching ? "Finding songs…" : "No songs found. Try a song or artist name.")
                            .font(Typography.body(15)).foregroundStyle(theme.palette.textSecondary)
                            .padding(.vertical, 24)
                    }
                    ForEach(visible) { track in
                        let exists = existingURIs.contains(track.uri) || added.contains(track.uri)
                        let selected = selection.contains { $0.uri == track.uri }
                        Button {
                            if selected { selection.removeAll { $0.uri == track.uri } }
                            else { selection.append(track) }
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkThumb(urlString: track.albumArt?.absoluteString, size: 46, corner: 8)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.name).font(Typography.semibold(14)).lineLimit(1)
                                    Text(track.artistNames).font(Typography.body(12))
                                        .foregroundStyle(theme.palette.textSecondary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                ProviderLogo(id: track.providerID, size: 20)
                                Image(systemName: exists || selected ? "checkmark.circle.fill" : "plus")
                                    .foregroundStyle(theme.palette.rose).frame(width: 32, height: 44)
                            }.foregroundStyle(theme.palette.text).padding(.vertical, 5)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(adding || exists)
                            .opacity(exists ? 0.55 : 1)
                            .accessibilityLabel("\(track.name), \(track.artistNames)")
                            .accessibilityValue(exists ? "Already added" : selected ? "Selected" : "Not selected")
                    }
                }.padding(18)
            }
            .background(theme.palette.bg.ignoresSafeArea())
            .navigationTitle("Add songs").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Songs or artists")
            .safeAreaInset(edge: .bottom) {
                Button { Task { await addSelection() } } label: {
                    Text(adding ? "Adding…" : "Add \(selection.count) song\(selection.count == 1 ? "" : "s")")
                        .font(Typography.semibold(16)).foregroundStyle(theme.palette.bg)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(theme.palette.rose, in: Capsule())
                }.buttonStyle(.plain).disabled(adding || selection.isEmpty)
                    .opacity(selection.isEmpty ? 0.5 : 1).padding(16)
                    .background(theme.palette.bg)
            }
            .onChange(of: query) { hits = []; searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { searching = false; return }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                let providers = await ProviderRegistry.connected()
                let found = await withTaskGroup(of: [UnifiedTrack].self) { group in
                    for provider in providers { group.addTask { await provider.search(q) } }
                    var all: [UnifiedTrack] = []
                    for await result in group { all += result }
                    return all
                }
                guard !Task.isCancelled, q == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                hits = found
                searching = false
            }
        }.tint(theme.palette.rose).heartableSheetChrome()
            .interactiveDismissDisabled(adding)
    }

    private func addSelection() async {
        guard !adding, !selection.isEmpty else { return }
        adding = true
        defer { adding = false }
        do {
            for track in selection {
                let insertionID = insertionIDs[track.uri] ?? UUID()
                insertionIDs[track.uri] = insertionID
                try await BackendAPI.shared.addMixtapeTrack(
                    mixtapeID: mixtapeID, id: insertionID, trackUri: track.uri, trackName: track.name,
                    artist: track.artistNames, albumArt: track.albumArt?.absoluteString,
                    durationMs: track.durationMs)
                added.insert(track.uri)
            }
            selection = []
            await onAdded()
            dismiss()
        } catch {
            selection.removeAll { added.contains($0.uri) }
            await onAdded()
            banners.error("Some songs couldn’t be added. Your remaining selection is ready to retry.")
        }
    }
}
