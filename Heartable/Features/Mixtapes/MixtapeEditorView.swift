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

    private var editable: Bool { mixtape?.mine ?? false }

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
        .navigationTitle(title.isEmpty ? "Mixtape" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editable {
                ToolbarItem(placement: .topBarTrailing) {
                    HeartableToolbarAction(
                        title: editMode == .active ? "Done" : "Edit"
                    ) {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showShare = true } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                    }
                    .tint(theme.palette.rose)
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            AddTracksSheet(mixtapeID: mixtapeID) { await load() }
        }
        .sheet(isPresented: $showShare) {
            ShareMixtapeSheet(mixtapeID: mixtapeID)
        }
        .task { await load() }
    }

    // MARK: List

    private var list: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section {
                ForEach(tracks) { t in trackRow(t) }
                    .onDelete(perform: deleteTracks)
                    .onMove(perform: moveTracks)

                if editable {
                    Button { showSearch = true } label: {
                        Label("Add tracks", systemImage: "plus.circle")
                            .font(Typography.semibold(15))
                            .foregroundStyle(theme.palette.rose)
                    }
                    .listRowBackground(theme.palette.bg)
                }
            } header: {
                Text("\(tracks.count) track\(tracks.count == 1 ? "" : "s")")
                    .font(Typography.semibold(12))
                    .foregroundStyle(theme.palette.textMuted)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.palette.bg)
    }

    private var header: some View {
        VStack(spacing: 12) {
            cover
            if editable {
                TextField("Mixtape title", text: $title)
                    .font(Typography.heading(24))
                    .foregroundStyle(theme.palette.text)
                    .multilineTextAlignment(.center)
                    .onSubmit { Task { await saveMeta() } }
                TextField("Add a description / dedication", text: $description, axis: .vertical)
                    .font(Typography.body(14))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .onSubmit { Task { await saveMeta() } }
            } else {
                Text(title.isEmpty ? "Untitled mixtape" : title)
                    .font(Typography.heading(24))
                    .foregroundStyle(theme.palette.text)
                    .multilineTextAlignment(.center)
                if !description.isEmpty {
                    Text(description)
                        .font(Typography.body(14))
                        .foregroundStyle(theme.palette.textSecondary)
                        .multilineTextAlignment(.center)
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

    private func load() async {
        let detail = await BackendAPI.shared.getMixtape(id: mixtapeID)
        loaded = true
        guard let detail else { mixtape = nil; return }
        mixtape = detail.mixtape
        tracks = detail.tracks.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        title = detail.mixtape.title ?? ""
        description = detail.mixtape.description ?? ""
    }

    private func saveMeta() async {
        guard editable else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await BackendAPI.shared.updateMixtape(
                id: mixtapeID,
                title: t.isEmpty ? "Untitled mixtape" : t,
                description: description
            )
        } catch { banners.error("Couldn’t save the mixtape details. Try again.") }
    }

    private func uploadCover(_ item: PhotosPickerItem) async {
        guard editable else { return }
        uploadingCover = true
        defer { uploadingCover = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let jpeg = ImageDownscale.jpeg(from: data) else { return }
            let url = try await BackendAPI.shared.uploadMixtapeImage(mixtapeID: mixtapeID, jpeg)
            try await BackendAPI.shared.updateMixtape(id: mixtapeID, coverUrl: .some(url))
            // NOTE: refresh the local cover by mutating the loaded DTO so the
            // AsyncImage re-renders without a full reload.
            mixtape?.coverUrl = url
        } catch {
            banners.error("Couldn’t save the mixtape cover. Try again.")
        }
    }

    @ViewBuilder
    private func trackRow(_ t: MixtapeTrackDTO) -> some View {
        UnifiedTrackRow(track: unified(t)) {
            Task { await player.play(tracks: tracks.map(unified),
                                     startingAt: tracks.firstIndex { $0.id == t.id },
                                     mode: prefs.mode, weights: prefs.weights) }
        }
        .listRowBackground(theme.palette.bg)
        .listRowSeparatorTint(theme.palette.border)
    }

    private func deleteTracks(_ offsets: IndexSet) {
        guard editable else { return }
        let removed = offsets.map { tracks[$0] }
        tracks.remove(atOffsets: offsets)
        Task {
            for t in removed { await BackendAPI.shared.deleteMixtapeTrack(id: t.id) }
        }
    }

    private func moveTracks(_ offsets: IndexSet, _ destination: Int) {
        guard editable else { return }
        tracks.move(fromOffsets: offsets, toOffset: destination)
        let ordered = tracks.enumerated().map { (id: $0.element.id, position: $0.offset) }
        Task { await BackendAPI.shared.reorderMixtapeTracks(ordered) }
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
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(theme.palette.rose)
                    .clipShape(Circle())
                    .overlay { Circle().stroke(theme.palette.bg, lineWidth: 2) }
                    .padding(8)
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
            if let urlString, let url = URL(string: urlString) {
                CachedArtworkImage(url: url) { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: 180, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
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

/// A search field that queries every connected provider, merges + dedupes the
/// results by `.key`, and adds a tapped result to the mixtape.
private struct AddTracksSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let mixtapeID: UUID
    let onAdded: () async -> Void

    @State private var query = ""
    @State private var hits: [UnifiedTrack] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(hits) { t in
                            Button {
                                Task { await add(t) }
                            } label: {
                                HStack(spacing: 12) {
                                    ArtworkThumb(urlString: t.albumArt?.absoluteString, size: 46, corner: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.name)
                                            .font(Typography.semibold(14))
                                            .foregroundStyle(theme.palette.text)
                                            .lineLimit(1)
                                        Text(t.artistNames)
                                            .font(Typography.body(12))
                                            .foregroundStyle(theme.palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(theme.palette.rose)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(t.name) by \(t.artistNames)")
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add tracks")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search connected services")
            .onSubmit(of: .search) { Task { await runSearch() } }
            .task(id: query) { await runSearch() }
        }
        .heartableSheetChrome()
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { hits = []; return }
        searching = true
        defer { searching = false }
        var merged: [String: UnifiedTrack] = [:]
        var order: [String] = []
        for provider in await ProviderRegistry.connected() {
            for t in await provider.search(q) where merged[t.key] == nil {
                merged[t.key] = t
                order.append(t.key)
            }
        }
        // Guard against a stale result from an earlier query.
        guard q == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        hits = order.compactMap { merged[$0] }
    }

    private func add(_ t: UnifiedTrack) async {
        try? await BackendAPI.shared.addMixtapeTrack(
            mixtapeID: mixtapeID,
            trackUri: t.uri,
            trackName: t.name,
            artist: t.artistNames,
            albumArt: t.albumArt?.absoluteString,
            durationMs: t.durationMs
        )
        await onAdded()
    }
}

// MARK: - Share sheet

/// Lists friends with a per-friend toggle reflecting current share membership;
/// flipping a toggle shares/unshares the mixtape with that friend.
private struct ShareMixtapeSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let mixtapeID: UUID

    @State private var friends: [FriendDTO] = []
    @State private var sharedWith: Set<UUID> = []
    @State private var loaded = false

    var body: some View {
        HeartableDrawer {
            VStack(alignment: .leading, spacing: 16) {
                Text("Share")
                    .font(Typography.heading(23))
                    .foregroundStyle(theme.palette.text)
                    VStack(alignment: .leading, spacing: 0) {
                        if !loaded {
                            ProgressView().tint(theme.palette.rose)
                        }
                        if friends.isEmpty && loaded {
                            Text("No friends yet. Add some from the Friends tab.")
                                .font(Typography.body(13))
                                .foregroundStyle(theme.palette.textSecondary)
                                .padding(.top, 24)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        ForEach(friends) { f in
                            if let fid = f.profile?.userId {
                                friendRow(f, friendID: fid)
                            }
                        }
                    }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .task { await load() }
    }

    private func friendRow(_ f: FriendDTO, friendID: UUID) -> some View {
        let on = sharedWith.contains(friendID)
        return Button {
            Task { await toggle(friendID, on: !on) }
        } label: {
            HStack(spacing: 12) {
                AvatarCircle(urlString: f.profile?.avatarUrl,
                             name: f.profile?.displayName, size: 38)
                Text(f.profile?.displayName ?? "Friend")
                    .font(Typography.medium(15))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(on ? theme.palette.rose : theme.palette.textMuted)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        async let f = BackendAPI.shared.listFriends()
        async let s = BackendAPI.shared.listMixtapeShares(id: mixtapeID)
        friends = await f
        sharedWith = Set(await s)
        loaded = true
    }

    private func toggle(_ friendID: UUID, on: Bool) async {
        if on {
            try? await BackendAPI.shared.shareMixtape(id: mixtapeID, friendID: friendID)
            sharedWith.insert(friendID)
        } else {
            await BackendAPI.shared.unshareMixtape(id: mixtapeID, friendID: friendID)
            sharedWith.remove(friendID)
        }
        dismiss()
    }
}
