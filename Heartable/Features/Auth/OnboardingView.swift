import SwiftUI
import PhotosUI

/// One-time setup wizard after first sign-in: set up your profile (photo, name,
/// handle), then connect your music services (connecting Apple Music is what
/// prompts for MusicKit access). Reached via the RootView gate; "Done" enters
/// the app. Steps are skippable and can all be redone later from Profile.
struct OnboardingView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(AuthStore.self) private var auth
    @Environment(MeStore.self) private var me
    @Environment(ProvidersStore.self) private var providers
    let onDone: () -> Void

    private enum Step: Int, CaseIterable { case profile, connect }
    @State private var step: Step = .profile

    // Profile fields.
    @State private var displayName = ""
    @State private var handle = ""
    @State private var avatarUrl: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false
    @State private var error: String?

    // Connect.
    @State private var busy: ProviderID?

    var body: some View {
        ZStack {
            theme.palette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                progressBar
                ScrollView {
                    Group {
                        switch step {
                        case .profile: profileStep
                        case .connect: connectStep
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
                footer
            }
        }
        .task {
            await me.load(userID: auth.userID)
            displayName = me.displayName == "Heartable user" ? "" : me.displayName
            handle = me.handle ?? ""
            avatarUrl = me.avatarUrlString
        }
    }

    // MARK: Progress

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? theme.palette.rose : theme.palette.surface)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: Step 1 — profile

    private var profileStep: some View {
        let avatarURLSnapshot = avatarUrl
        let displayNameSnapshot = displayName
        let isUploading = uploading

        return VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Set up your profile")
                    .font(Typography.heading(26))
                    .foregroundStyle(theme.palette.text)
                Text("This is how friends find and recognize you on Heartable.")
                    .font(Typography.body(14))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)

            PhotosPicker(selection: $photoItem, matching: .images) {
                OnboardingAvatarPickerLabel(
                    urlString: avatarURLSnapshot,
                    name: displayNameSnapshot,
                    isUploading: isUploading
                )
            }
            .buttonStyle(.plain)
            .disabled(uploading)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await uploadAvatar(item) }
            }

            fieldCard {
                fieldLabel("Display name")
                TextField("What friends call you", text: $displayName)
                    .font(Typography.body(15)).foregroundStyle(theme.palette.text)
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                Divider().overlay(theme.palette.border)
                fieldLabel("Handle")
                HStack(spacing: 4) {
                    Text("@").font(Typography.semibold(15)).foregroundStyle(theme.palette.textMuted)
                    TextField("username", text: $handle)
                        .font(Typography.body(15)).foregroundStyle(theme.palette.text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: handle) { _, new in
                            handle = new.filter { $0.isLetter || $0.isNumber || $0 == "_" }
                        }
                }
            }

            if let error {
                Text(error).font(Typography.body(13)).foregroundStyle(theme.palette.danger)
            }
        }
    }

    // MARK: Step 2 — connect

    private var connectStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Connect your music")
                    .font(Typography.heading(26))
                    .foregroundStyle(theme.palette.text)
                Text("Pull your library, playlists, and stats into one place. Apple Music will ask for access when you connect it. You can add more later in Profile.")
                    .font(Typography.body(14))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)

            VStack(spacing: 10) {
                ForEach(ProviderCatalog.all.filter { $0.status == .live }) { entry in
                    connectRow(entry)
                }
            }

            if let error {
                Text(error).font(Typography.body(13)).foregroundStyle(theme.palette.danger)
            }
        }
    }

    private func connectRow(_ entry: ProviderCatalogEntry) -> some View {
        let connected = providers.isConnected(entry.id)
        return HStack(spacing: 12) {
            ProviderBadge(id: entry.id, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label).font(Typography.semibold(15)).foregroundStyle(theme.palette.text)
                Text(connected ? "Connected" : entry.blurb)
                    .font(Typography.body(12))
                    .foregroundStyle(connected ? theme.palette.rose : theme.palette.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if busy == entry.id {
                ProgressView().controlSize(.small)
            } else {
                Button(connected ? "Connected" : "Connect") { connect(entry) }
                    .font(Typography.semibold(13))
                    .foregroundStyle(connected ? theme.palette.textSecondary : .white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(connected ? theme.palette.surface : theme.palette.rose, in: Capsule())
                    .disabled(connected)
            }
        }
        .padding(12)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(theme.palette.border, lineWidth: 1))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if step == .connect {
                Button("Back") { withAnimation { step = .profile } }
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.textSecondary)
                    .padding(.vertical, 15).padding(.horizontal, 20)
            }
            Button(action: advance) {
                HStack {
                    if saving { ProgressView().tint(.white) }
                    Text(primaryLabel).font(Typography.semibold(16))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(theme.palette.rose)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.full))
            }
            .buttonStyle(.plain)
            .disabled(saving || uploading)
        }
        .overlay(alignment: .topTrailing) {
            if step == .profile {
                Button("Skip", action: { withAnimation { step = .connect } })
                    .font(Typography.semibold(13))
                    .foregroundStyle(theme.palette.textMuted)
                    .offset(y: -28)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 26)
        .padding(.top, 8)
    }

    private var primaryLabel: String {
        switch step {
        case .profile: return "Continue"
        case .connect: return "Done"
        }
    }

    private func advance() {
        switch step {
        case .profile:
            Task {
                await saveProfile()
                withAnimation { step = .connect }
            }
        case .connect:
            onDone()
        }
    }

    // MARK: Actions

    private func connect(_ entry: ProviderCatalogEntry) {
        busy = entry.id
        Task {
            do { try await ProviderRegistry.provider(for: entry.id).connect() }
            catch { self.error = error.localizedDescription }
            await providers.refresh()
            busy = nil
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        uploading = true
        error = nil
        defer { uploading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let jpeg = ImageDownscale.jpeg(from: data) else {
                error = "Couldn't read that image."
                return
            }
            let url = try await BackendAPI.shared.uploadAvatar(jpeg)
            try await BackendAPI.shared.updateMyProfile(avatarUrl: .some(url))
            avatarUrl = url
            me.setAvatar(url, userID: auth.userID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveProfile() async {
        saving = true
        error = nil
        defer { saving = false }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Nothing entered yet is fine; they can fill it in later from Profile.
        guard !name.isEmpty || !tag.isEmpty else { return }
        do {
            try await BackendAPI.shared.updateMyProfile(
                displayName: .some(name.isEmpty ? nil : name),
                handle: .some(tag.isEmpty ? nil : tag)
            )
            me.setNameHandle(displayName: name.isEmpty ? nil : name,
                             handle: tag.isEmpty ? nil : tag, userID: auth.userID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Field helpers

    @ViewBuilder
    private func fieldCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay { RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(theme.palette.border, lineWidth: 1) }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typography.semibold(11))
            .foregroundStyle(theme.palette.textMuted)
    }
}

private struct OnboardingAvatarPickerLabel: View {
    @Environment(ThemeStore.self) private var theme

    let urlString: String?
    let name: String
    let isUploading: Bool

    var body: some View {
        ZStack {
            AvatarCircle(urlString: urlString, name: name, size: 110)
                .opacity(isUploading ? 0.5 : 1)
            Image(systemName: "camera.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(theme.palette.rose)
                .clipShape(Circle())
                .overlay { Circle().stroke(theme.palette.bg, lineWidth: 2) }
                .offset(x: 38, y: 38)
            if isUploading {
                ProgressView().tint(.white)
            }
        }
        .frame(width: 110, height: 110)
    }
}
