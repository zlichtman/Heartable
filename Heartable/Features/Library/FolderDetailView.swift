import SwiftUI

/// A playlist folder's contents. Folders are a Heartable-local grouping (Spotify
/// style), so the items are snapshots stored in Supabase — tapping one opens the
/// live playlist via PlaylistDetailView (built from the stored snapshot).
/// Supports rename, delete, and swipe-to-remove a playlist. Ported from the RN
/// FolderScreen.
struct FolderDetailView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let folder: FolderDTO
    /// Called after a rename or delete so the Library grid that pushed this view
    /// can refresh (otherwise the old name / deleted tile lingers until refresh).
    var onChanged: (() -> Void)?

    @State private var name: String
    @State private var items: [FolderItemDTO] = []
    @State private var loading = true
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false
    @State private var showingActions = false
    @State private var pendingFolderAction: String?

    init(folder: FolderDTO, onChanged: (() -> Void)? = nil) {
        self.folder = folder
        self.onChanged = onChanged
        _name = State(initialValue: folder.name)
    }

    var body: some View {
        List {
            Section {
                // The hero scrolls away with the list (first row, not a pinned
                // section header) so the playlists are fully readable.
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if loading {
                    HStack {
                        Spacer()
                        ProgressView().tint(theme.palette.rose)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if items.isEmpty {
                    Text("No playlists yet. Long-press a playlist in your library to add it here.")
                        .font(Typography.body(14))
                        .foregroundStyle(theme.palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(items) { item in
                        NavigationLink(value: playlist(from: item)) {
                            itemRow(item)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await remove(item) }
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // The playlist destination is already registered by the ancestor LibraryView
        // stack; re-declaring it here is a duplicate (SwiftUI ignores the inner one).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingActions = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(theme.palette.text)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Folder options")
            }
        }
        .sheet(
            isPresented: $showingActions,
            onDismiss: presentPendingFolderAction
        ) {
            HeartableChoiceSheet(
                title: "Folder options",
                items: [
                    HeartableChoiceItem(
                        id: "rename",
                        icon: "pencil",
                        title: "Rename"
                    ),
                    HeartableChoiceItem(
                        id: "delete",
                        icon: "trash.fill",
                        title: "Delete folder",
                        isDestructive: true
                    ),
                ],
                onCancel: { showingActions = false },
                onSelect: { item in
                    pendingFolderAction = item.id
                    showingActions = false
                }
            )
        }
        .sheet(isPresented: $renaming) {
            HeartablePromptSheet(
                icon: "folder.fill",
                title: "Rename folder",
                message: "Choose a name for this group of playlists.",
                placeholder: "Folder name",
                text: $newName,
                actionTitle: "Save",
                onCancel: { renaming = false },
                onSubmit: {
                    let next = newName
                    renaming = false
                    Task { await rename(next) }
                }
            )
        }
        .sheet(isPresented: $confirmingDelete) {
            HeartableDestructiveConfirmation(
                icon: "trash.fill",
                title: "Delete folder?",
                message: "“\(name)” will be removed. Its playlists stay in your library.",
                confirmTitle: "Delete folder",
                cancelTitle: "Keep folder",
                onCancel: { confirmingDelete = false },
                onConfirm: { Task { await deleteFolder() } }
            )
        }
        .task(id: folder.id) { await load() }
    }

    private func presentPendingFolderAction() {
        switch pendingFolderAction {
        case "rename":
            newName = name
            renaming = true
        case "delete":
            confirmingDelete = true
        default:
            break
        }
        pendingFolderAction = nil
    }

    private var header: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(theme.palette.rose.opacity(0.13))
                Image(systemName: "folder.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(theme.palette.rose)
            }
            .frame(width: 64, height: 64)
            .padding(.bottom, 12)

            Text(name)
                .font(Typography.heading(24))
                .foregroundStyle(theme.palette.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("\(items.count) playlist\(items.count == 1 ? "" : "s")")
                .font(Typography.semibold(12))
                .foregroundStyle(theme.palette.textMuted)
                .textCase(.uppercase)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
    }

    private func itemRow(_ item: FolderItemDTO) -> some View {
        HStack(spacing: 12) {
            CoverArt(
                url: URL(string: item.image ?? ""),
                size: 52,
                corner: Theme.Radius.sm,
                placeholder: "music.note.list"
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
                Text((item.trackCount ?? 0) > 0 ? "\(item.trackCount ?? 0) tracks" : "Playlist")
                    .font(Typography.body(12))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
    }

    /// Build a live UnifiedPlaylist from the stored snapshot.
    private func playlist(from item: FolderItemDTO) -> UnifiedPlaylist {
        let provider = ProviderID(rawValue: item.providerId) ?? .spotify
        return UnifiedPlaylist(
            key: item.playlistKey,
            providerID: provider,
            playlistID: item.playlistId,
            name: item.name,
            description: nil,
            image: URL(string: item.image ?? ""),
            trackCount: item.trackCount ?? 0,
            owner: item.ownerName
        )
    }

    private func load() async {
        loading = true
        items = await BackendAPI.shared.listFolderItems(folderID: folder.id)
        loading = false
    }

    private func rename(_ next: String) async {
        let trimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else { return }
        let previous = name
        name = trimmed
        do {
            try await BackendAPI.shared.renameFolder(id: folder.id, name: trimmed)
            onChanged?()
        } catch {
            name = previous
        }
    }

    private func deleteFolder() async {
        do {
            try await BackendAPI.shared.deleteFolder(id: folder.id)
            onChanged?()
            dismiss()
        } catch {
            // Stay on screen if the delete failed.
        }
    }

    private func remove(_ item: FolderItemDTO) async {
        items.removeAll { $0.playlistKey == item.playlistKey }
        do {
            try await BackendAPI.shared.removePlaylistFromFolder(folderID: folder.id, key: item.playlistKey)
        } catch {
            await load()
        }
    }
}
