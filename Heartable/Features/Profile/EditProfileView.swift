import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Edit display name + handle, plus an avatar source chooser. Every selected
/// image is downscaled to a <=1024px JPEG, uploaded to the `avatars` bucket,
/// and persisted on the profile. Saving returns to the profile.
struct EditProfileView: View {
    private enum Field: Hashable {
        case displayName
        case handle
    }

    private enum PhotoSource: String {
        case library
        case camera
        case files
    }

    @Environment(ThemeStore.self) private var theme
    @Environment(AuthStore.self) private var auth
    @Environment(MeStore.self) private var me
    @Environment(BannerCenter.self) private var banners
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var handle = ""
    @State private var initialDisplayName = ""
    @State private var initialHandle = ""
    @State private var playlistChoices: [UnifiedPlaylist] = []
    @State private var selectedPlaylistKeys: [String] = []
    @State private var initialPlaylistKeys: [String] = []
    @State private var profileModules = ProfileModulePreferenceDTO.defaults
    @State private var initialProfileModules = ProfileModulePreferenceDTO.defaults
    @State private var profileCurationLoaded = false
    @State private var avatarUrl: String?
    @State private var loaded = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var loadErrorMessage: String?
    @State private var playlistLoadErrorMessage: String?

    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var showingPhotoSourceChooser = false
    @State private var pendingPhotoSource: PhotoSource?
    @State private var showingPhotoLibrary = false
    @State private var showingCamera = false
    @State private var showingFileImporter = false
    @State private var showingDiscardConfirmation = false
    @State private var loadingPlaylists = false
    @State private var profileLibrary = LibraryStore()
    @FocusState private var focusedField: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if loaded {
                    avatarEditor
                    identityForm
                    featuredPlaylistsForm
                    profileLayoutForm

                    if let errorMessage {
                        errorCallout(errorMessage)
                    }
                } else if let loadErrorMessage {
                    loadFailure(message: loadErrorMessage)
                } else {
                    ProgressView("Loading profile…")
                        .tint(theme.palette.rose)
                        .foregroundStyle(theme.palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveBar
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HeartableNavigationButton(
                    kind: .back,
                    drawsSurface: false,
                    action: attemptDismiss
                )
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                HeartableToolbarAction(title: "Done") {
                    focusedField = nil
                }
            }
        }
        .sheet(isPresented: $showingDiscardConfirmation) {
            HeartableDestructiveConfirmation(
                icon: "arrow.uturn.backward",
                title: "Discard profile changes?",
                message: "Your unsaved name, handle, playlist, and layout changes will be lost.",
                confirmTitle: "Discard changes",
                cancelTitle: "Keep editing",
                onCancel: { showingDiscardConfirmation = false },
                onConfirm: {
                    showingDiscardConfirmation = false
                    dismiss()
                }
            )
        }
        .sheet(
            isPresented: $showingPhotoSourceChooser,
            onDismiss: presentPendingPhotoSource
        ) {
            HeartableChoiceSheet(
                title: "Change profile photo",
                items: [
                    HeartableChoiceItem(
                        id: PhotoSource.library.rawValue,
                        icon: "photo.on.rectangle",
                        title: "Photo Library"
                    ),
                    HeartableChoiceItem(
                        id: PhotoSource.camera.rawValue,
                        icon: "camera.fill",
                        title: "Take Photo"
                    ),
                    HeartableChoiceItem(
                        id: PhotoSource.files.rawValue,
                        icon: "folder.fill",
                        title: "Choose File"
                    ),
                ],
                onCancel: { showingPhotoSourceChooser = false },
                onSelect: { item in
                    pendingPhotoSource = PhotoSource(rawValue: item.id)
                    showingPhotoSourceChooser = false
                }
            )
        }
        .photosPicker(
            isPresented: $showingPhotoLibrary,
            selection: $photoItem,
            matching: .images
        )
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await uploadAvatar(photoItem: item) }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            ProfilePhotoCameraPicker(
                onImageData: { data in
                    showingCamera = false
                    Task { await uploadAvatar(data: data) }
                },
                onCancel: {
                    showingCamera = false
                }
            )
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleAvatarFileImport(result)
        }
        .task { await load() }
    }

    // MARK: - Editor sections

    private var avatarEditor: some View {
        let currentAvatarURL = avatarUrl
        let currentDisplayName = displayName
        let isUploading = uploading
        let palette = theme.palette

        return Button {
            showingPhotoSourceChooser = true
        } label: {
            VStack(spacing: 14) {
                ZStack {
                    AvatarCircle(urlString: currentAvatarURL, name: currentDisplayName, size: 116)
                        .opacity(isUploading ? 0.45 : 1)

                    if isUploading {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.large)
                    }

                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(palette.rose, in: Circle())
                        .overlay(Circle().stroke(palette.bg, lineWidth: 3))
                        .offset(x: 42, y: 42)
                }
                .frame(width: 124, height: 124)

                VStack(spacing: 4) {
                    Text(isUploading ? "Uploading photo…" : "Change profile photo")
                        .font(Typography.semibold(15))
                        .foregroundStyle(isUploading ? palette.textMuted : palette.rose)

                    Text("Photo changes save immediately.")
                        .font(Typography.body(12))
                        .foregroundStyle(palette.textMuted)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(uploading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(uploading ? "Uploading profile photo" : "Change profile photo")
        .accessibilityHint(
            "Choose a photo from your library, camera, or files. "
                + "Photo changes save immediately."
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var identityForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROFILE DETAILS")
                    .font(Typography.semibold(12))
                    .tracking(1)
                    .foregroundStyle(theme.palette.textMuted)

                Text("This is how you appear to friends.")
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
            }

            fieldCard {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Display name")
                    TextField("What friends call you", text: $displayName)
                        .font(Typography.body(16))
                        .foregroundStyle(theme.palette.text)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .textContentType(.name)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .displayName)
                        .onSubmit { focusedField = .handle }
                        .accessibilityLabel("Display name")
                }

                Divider().overlay(theme.palette.border)

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Handle")
                    HStack(spacing: 4) {
                        Text("@")
                            .font(Typography.semibold(16))
                            .foregroundStyle(theme.palette.textMuted)
                            .accessibilityHidden(true)

                        TextField("username", text: $handle)
                            .font(Typography.body(16))
                            .foregroundStyle(theme.palette.text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .submitLabel(.done)
                            .focused($focusedField, equals: .handle)
                            .onSubmit { focusedField = nil }
                            .onChange(of: handle) { _, new in
                                let sanitized = sanitizeHandle(new)
                                if sanitized != new { handle = sanitized }
                            }
                            .accessibilityLabel("Handle")
                    }

                    Text("Letters, numbers, and underscores only")
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textMuted)
                }
            }
        }
    }

    private var featuredPlaylistsForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FEATURED PLAYLISTS")
                    .font(Typography.semibold(12))
                    .tracking(1)
                    .foregroundStyle(theme.palette.textMuted)

                Text("Choose up to six playlists, in the order you want friends to see them.")
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if loadingPlaylists && playlistChoices.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.palette.rose)
                    Text("Loading your playlists…")
                        .font(Typography.body(13))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    theme.palette.card,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.lg)
                )
            } else if let playlistLoadErrorMessage, playlistChoices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label(playlistLoadErrorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(Typography.body(13))
                        .foregroundStyle(theme.palette.danger)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        guard let userID = auth.userID else { return }
                        Task { await loadPlaylistChoices(userID: userID, force: true) }
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .font(Typography.semibold(13))
                            .foregroundStyle(theme.palette.rose)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    theme.palette.card,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.lg)
                )
            } else if playlistChoices.isEmpty {
                Text("Connect a music service with playlists to feature them here.")
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textMuted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        theme.palette.card,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(orderedPlaylistChoices) { playlist in
                        playlistChoiceRow(playlist)
                        if playlist.key != orderedPlaylistChoices.last?.key {
                            Divider()
                                .overlay(theme.palette.border)
                                .padding(.leading, 74)
                        }
                    }
                }
                .background(theme.palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .stroke(theme.palette.border, lineWidth: 1)
                }
            }

            Text("\(selectedPlaylistKeys.count) of 6 selected")
                .font(Typography.medium(12))
                .foregroundStyle(
                    selectedPlaylistKeys.count == 6
                        ? theme.palette.rose
                        : theme.palette.textMuted
                )
        }
    }

    private func playlistChoiceRow(_ playlist: UnifiedPlaylist) -> some View {
        let selectionIndex = selectedPlaylistKeys.firstIndex(of: playlist.key)
        let limitReached = selectedPlaylistKeys.count >= 6
        let unavailable = selectionIndex == nil && limitReached
        return Button {
            togglePlaylist(playlist)
        } label: {
            HStack(spacing: 12) {
                CoverArt(
                    url: playlist.image,
                    size: 48,
                    placeholder: "music.note.list"
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(Typography.semibold(14))
                        .foregroundStyle(theme.palette.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ProviderCatalog.entry(playlist.providerID)?.label ?? playlist.providerID.rawValue)
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textMuted)
                }

                Spacer(minLength: 8)

                if let selectionIndex {
                    Text("\(selectionIndex + 1)")
                        .font(Typography.semibold(12))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(theme.palette.rose, in: Circle())
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.palette.border)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
            .opacity(unavailable ? 0.42 : 1)
        }
        .buttonStyle(.plain)
        .disabled(unavailable)
        .accessibilityLabel(playlist.name)
        .accessibilityValue(
            selectionIndex.map { "Featured position \($0 + 1)" }
                ?? (unavailable ? "Selection limit reached" : "Not featured")
        )
        .accessibilityHint(
            selectionIndex != nil
                ? "Removes from your public profile"
                : unavailable
                ? "Unselect a featured playlist to choose this one"
                : "Adds to your public profile"
        )
    }

    private var profileLayoutForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROFILE LAYOUT")
                    .font(Typography.semibold(12))
                    .tracking(1)
                    .foregroundStyle(theme.palette.textMuted)

                Text("Choose what appears and arrange the sections in your profile.")
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if profileCurationLoaded {
                VStack(spacing: 0) {
                    ForEach(Array(profileModules.enumerated()), id: \.element.id) { index, item in
                        profileModuleRow(item, at: index)
                        if index < profileModules.count - 1 {
                            Divider()
                                .overlay(theme.palette.border)
                                .padding(.leading, 62)
                        }
                    }
                }
                .background(theme.palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .stroke(theme.palette.border, lineWidth: 1)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.palette.rose)
                    Text("Loading profile layout…")
                        .font(Typography.body(13))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    theme.palette.card,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.lg)
                )
            }
        }
    }

    private func profileModuleRow(
        _ item: ProfileModulePreferenceDTO,
        at index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        item.isVisible
                            ? theme.palette.roseDim
                            : theme.palette.surface
                    )
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: item.module.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(
                                item.isVisible
                                    ? theme.palette.rose
                                    : theme.palette.textMuted
                            )
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.module.title)
                        .font(Typography.semibold(14))
                        .foregroundStyle(theme.palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.module.subtitle)
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button {
                    toggleModuleVisibility(at: index)
                } label: {
                    Label(
                        item.isVisible ? "Visible" : "Hidden",
                        systemImage: item.isVisible ? "eye.fill" : "eye.slash.fill"
                    )
                    .font(Typography.semibold(12))
                    .foregroundStyle(
                        item.isVisible ? theme.palette.rose : theme.palette.textSecondary
                    )
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(
                        item.isVisible ? theme.palette.roseDim : theme.palette.surface,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().stroke(
                            item.isVisible ? theme.palette.rose.opacity(0.32) : theme.palette.border,
                            lineWidth: 1
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(item.module.title), \(item.isVisible ? "visible" : "hidden")"
                )
                .accessibilityHint(
                    item.isVisible ? "Hides this profile section" : "Shows this profile section"
                )

                Spacer(minLength: 6)

                reorderButton(
                    systemImage: "arrow.up",
                    label: "Move \(item.module.title) up",
                    disabled: index == 0
                ) {
                    moveModule(from: index, offset: -1)
                }
                reorderButton(
                    systemImage: "arrow.down",
                    label: "Move \(item.module.title) down",
                    disabled: index == profileModules.count - 1
                ) {
                    moveModule(from: index, offset: 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(item.isVisible ? 1 : 0.72)
    }

    private func reorderButton(
        systemImage: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.palette.textSecondary)
                .frame(width: 44, height: 44)
                .background(theme.palette.surface, in: Circle())
                .overlay(Circle().stroke(theme.palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.32 : 1)
        .accessibilityLabel(label)
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(theme.palette.border)

            Button(action: {
                focusedField = nil
                Task { await save() }
            }) {
                HStack(spacing: 9) {
                    if saving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                    }

                    Text(saving ? "Saving…" : "Save changes")
                        .font(Typography.semibold(16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(theme.palette.rose, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
            .accessibilityHint(hasChanges ? "Saves your profile updates" : "No profile changes to save")
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 652)
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func errorCallout(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(Typography.body(13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.palette.danger)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.danger.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .combine)
    }

    private func loadFailure(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(theme.palette.danger)

            VStack(spacing: 5) {
                Text("Couldn’t load your profile")
                    .font(Typography.semibold(17))
                    .foregroundStyle(theme.palette.text)
                Text(message)
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await load() }
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(Typography.semibold(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(theme.palette.rose, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(theme.palette.border, lineWidth: 1)
        }
    }

    // MARK: - Field helpers

    @ViewBuilder
    private func fieldCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(theme.palette.border, lineWidth: 1)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Typography.semibold(13))
            .foregroundStyle(theme.palette.textSecondary)
    }

    // MARK: - Derived

    private var normalizedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedHandle: String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var hasChanges: Bool {
        normalizedDisplayName != initialDisplayName
            || normalizedHandle != initialHandle
            || selectedPlaylistKeys != initialPlaylistKeys
            || profileModules != initialProfileModules
    }

    private var canSave: Bool {
        loaded && !saving && !uploading && hasChanges
    }

    private func attemptDismiss() {
        focusedField = nil
        if hasChanges {
            showingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    /// Keep row positions stable while the user taps. Selection order is carried
    /// by `selectedPlaylistKeys` and shown by the numbered badges; moving a row
    /// under the user's finger after every tap made the picker feel jumpy.
    private var orderedPlaylistChoices: [UnifiedPlaylist] {
        playlistChoices
    }

    private func togglePlaylist(_ playlist: UnifiedPlaylist) {
        if let index = selectedPlaylistKeys.firstIndex(of: playlist.key) {
            selectedPlaylistKeys.remove(at: index)
            return
        }
        guard selectedPlaylistKeys.count < 6 else {
            errorMessage = "Choose up to six featured playlists."
            return
        }
        selectedPlaylistKeys.append(playlist.key)
        errorMessage = nil
    }

    private func toggleModuleVisibility(at index: Int) {
        guard profileModules.indices.contains(index) else { return }
        profileModules[index].isVisible.toggle()
    }

    private func moveModule(from index: Int, offset: Int) {
        let destination = index + offset
        guard profileModules.indices.contains(index),
              profileModules.indices.contains(destination) else { return }
        profileModules.swapAt(index, destination)
    }

    /// Match the RN editor: lower-friendly handle, alphanumerics + underscore only.
    private func sanitizeHandle(_ raw: String) -> String {
        raw.filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    // MARK: - Load / save

    private func load() async {
        loaded = false
        loadErrorMessage = nil

        guard let uid = auth.userID else {
            loadErrorMessage = "Sign in again to edit your profile."
            return
        }

        do {
            let existing = me.profile?.userId == uid
                ? me.profile
                : try await BackendAPI.shared.getMyProfile(userID: uid)
            if let p = existing {
                displayName = p.displayName ?? ""
                handle = p.handle ?? ""
                avatarUrl = p.avatarUrl
            }
            initialDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            initialHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            loaded = true
            Task { await loadPlaylistChoices(userID: uid) }
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func loadPlaylistChoices(userID: UUID, force: Bool = false) async {
        loadingPlaylists = true
        profileCurationLoaded = false
        playlistLoadErrorMessage = nil
        defer { loadingPlaylists = false }

        do {
            async let savedTask = me.loadFeaturedPlaylists(userID: userID, force: force)
            await profileLibrary.loadAll()
            let savedPlaylists = try await savedTask
            guard auth.userID == userID else { return }

            let providerPlaylists = profileLibrary.playlists.filter { !$0.isMixtape }
            var seen = Set<String>()
            playlistChoices = (savedPlaylists + providerPlaylists).filter {
                seen.insert($0.key).inserted
            }
            selectedPlaylistKeys = savedPlaylists.map(\.key)
            initialPlaylistKeys = selectedPlaylistKeys
            profileModules = me.profileModules
            initialProfileModules = profileModules
            profileCurationLoaded = true
        } catch {
            guard auth.userID == userID else { return }
            playlistLoadErrorMessage = error.localizedDescription
        }
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentAvatarError("A camera isn’t available on this device.")
            return
        }
        showingCamera = true
    }

    private func presentPendingPhotoSource() {
        guard let source = pendingPhotoSource else { return }
        pendingPhotoSource = nil
        switch source {
        case .library:
            showingPhotoLibrary = true
        case .camera:
            presentCamera()
        case .files:
            showingFileImporter = true
        }
    }

    private func handleAvatarFileImport(
        _ result: Result<[URL], any Error>
    ) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await uploadAvatar(fileURL: url) }
        case .failure(let error):
            guard !Self.isUserCancellation(error) else { return }
            presentAvatarError(
                "Couldn’t open that file. \(error.localizedDescription)"
            )
        }
    }

    private func uploadAvatar(photoItem: PhotosPickerItem) async {
        await uploadAvatar {
            try await photoItem.loadTransferable(type: Data.self)
        }
    }

    private func uploadAvatar(data: Data) async {
        await uploadAvatar { data }
    }

    private func uploadAvatar(fileURL: URL) async {
        await uploadAvatar {
            try await Task.detached(priority: .userInitiated) {
                let hasAccess = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        fileURL.stopAccessingSecurityScopedResource()
                    }
                }
                return try Data(contentsOf: fileURL)
            }.value
        }
    }

    private func uploadAvatar(
        loadData: () async throws -> Data?
    ) async {
        guard !uploading else { return }
        uploading = true
        errorMessage = nil
        defer { uploading = false }
        do {
            guard let data = try await loadData(),
                  let jpeg = ImageDownscale.jpeg(from: data) else {
                presentAvatarError("Couldn’t read that image.")
                return
            }
            let url = try await BackendAPI.shared.uploadAvatar(jpeg)
            try await BackendAPI.shared.updateMyProfile(avatarUrl: .some(url))
            avatarUrl = url
            me.setAvatar(url, userID: auth.userID)   // propagate app-wide
            banners.success("Profile photo updated")
        } catch {
            guard !Self.isUserCancellation(error) else { return }
            presentAvatarError(error.localizedDescription)
        }
    }

    private func presentAvatarError(_ message: String) {
        errorMessage = message
        banners.error(message)
    }

    private static func isUserCancellation(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.userCancelled.rawValue
    }

    private func save() async {
        saving = true
        errorMessage = nil
        let name = normalizedDisplayName
        let tag = normalizedHandle
        do {
            if name != initialDisplayName || tag != initialHandle {
                try await BackendAPI.shared.updateMyProfile(
                    displayName: .some(name.isEmpty ? nil : name),
                    handle: .some(tag.isEmpty ? nil : tag)
                )
                me.setNameHandle(
                    displayName: name.isEmpty ? nil : name,
                    handle: tag.isEmpty ? nil : tag,
                    userID: auth.userID
                )
                initialDisplayName = name
                initialHandle = tag
            }
            if selectedPlaylistKeys != initialPlaylistKeys
                || profileModules != initialProfileModules {
                let byKey = Dictionary(
                    uniqueKeysWithValues: playlistChoices.map { ($0.key, $0) }
                )
                let selected = selectedPlaylistKeys.compactMap { byKey[$0] }
                guard selected.count == selectedPlaylistKeys.count else {
                    throw BackendError.message(
                        "One selected playlist is no longer available. Review your selection and try again."
                    )
                }
                try await BackendAPI.shared.updateProfileCuration(
                    playlists: selected,
                    modules: profileModules
                )
                me.setProfileCuration(
                    playlists: selected,
                    modules: profileModules,
                    userID: auth.userID
                )
                initialPlaylistKeys = selectedPlaylistKeys
                initialProfileModules = profileModules
            }
            saving = false
            banners.success("Profile saved")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            banners.error(error.localizedDescription)
            saving = false
        }
    }
}

/// Shared image helper: decode arbitrary picked image data, scale its longest
/// edge down to <=1024px, and re-encode as JPEG (quality 0.85). Returns nil if
/// the data isn't a decodable image. Used by avatar + mixtape-cover uploads.
enum ImageDownscale {
    static func jpeg(from data: Data, maxEdge: CGFloat = 1024, quality: CGFloat = 0.85) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scaled: UIImage
        if longest > maxEdge, longest > 0 {
            let factor = maxEdge / longest
            let newSize = CGSize(width: image.size.width * factor,
                                 height: image.size.height * factor)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            scaled = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            scaled = image
        }
        return scaled.jpegData(compressionQuality: quality)
    }
}
