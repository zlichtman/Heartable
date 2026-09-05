import SwiftUI

/// Destructive-zone account actions: sign out, and a full data wipe. Both gate
/// behind a confirmation; the wipe shows a spinner and a result line since it
/// can take a moment to cascade through every owned table.
struct AccountView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(AuthStore.self) private var auth
    @Environment(BannerCenter.self) private var banners
    @Environment(BackupScheduler.self) private var backupScheduler
    @Environment(NowPlayingSync.self) private var nowPlayingSync
    @Environment(TopTracksRepository.self) private var topTracks
    @Environment(WeeklyRecapStore.self) private var weeklyRecap
    @Environment(LibrarySessionStore.self) private var librarySession
    @Environment(PlaylistTracksRepository.self) private var playlistTracks
    @Environment(SkipStore.self) private var skips

    @State private var confirmSignOut = false
    @State private var signingOut = false
    @State private var confirmClear = false
    @State private var clearing = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var clearingArtworkCache = false
    @State private var artworkCacheBytes: Int64 = 0
    @State private var resultMessage: String?
    @State private var resultIsError = false

    var body: some View {
        SettingsScaffold(title: "Account") {
            sectionLabel("STORAGE")

            Button {
                Task { await clearArtworkCache() }
            } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.palette.roseDim)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: "photo.stack.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.palette.rose)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear artwork cache")
                            .font(Typography.semibold(15))
                            .foregroundStyle(theme.palette.text)
                        Text(artworkCacheDescription)
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textMuted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if clearingArtworkCache {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.palette.rose)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(theme.palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(theme.palette.border, lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(clearingArtworkCache)
            .accessibilityHint("Removes downloaded album and artist images. They reload as needed.")

            Text("Removes downloaded artwork only. Your library, history, services, and account stay intact.")
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            sectionLabel("ACCOUNT ACTIONS")
                .padding(.top, 8)

            Button {
                confirmSignOut = true
            } label: {
                SettingsRow(icon: "rectangle.portrait.and.arrow.right", label: "Sign out")
            }
            .buttonStyle(.plain)
            .disabled(clearing || deleting || signingOut)

            Button {
                confirmClear = true
            } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.palette.danger)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear all data")
                            .font(Typography.semibold(15))
                            .foregroundStyle(theme.palette.danger)
                        Text("Wipes snapshots, mixtapes, and history")
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if clearing {
                        ProgressView().tint(theme.palette.danger)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(theme.palette.danger.opacity(0.4), lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(clearing)

            Button {
                confirmDelete = true
            } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.palette.danger)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete account")
                            .font(Typography.semibold(15))
                            .foregroundStyle(theme.palette.danger)
                        Text("Permanently removes your account and all data")
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if deleting {
                        ProgressView().tint(theme.palette.danger)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(theme.palette.danger.opacity(0.4), lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(deleting || clearing)

            if let resultMessage {
                Text(resultMessage)
                    .font(Typography.body(13))
                    .foregroundStyle(resultIsError ? theme.palette.danger : theme.palette.textSecondary)
                    .padding(.top, 2)
            }

            Text(versionString)
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
        }
        .task { await updateArtworkCacheSize() }
        .sheet(isPresented: $confirmSignOut) {
            HeartableDestructiveConfirmation(
                icon: "rectangle.portrait.and.arrow.right",
                title: "Sign out?",
                message: "Your Heartable data and connected music services stay with your account.",
                confirmTitle: "Sign out",
                cancelTitle: "Stay signed in",
                isBusy: signingOut,
                onCancel: {
                    confirmSignOut = false
                },
                onConfirm: {
                    signingOut = true
                    Task {
                        do {
                            try await auth.signOut()
                            signingOut = false
                            confirmSignOut = false
                        } catch {
                            signingOut = false
                            banners.error("Couldn't sign out. Please try again.")
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $confirmClear) {
            HeartableDestructiveConfirmation(
                icon: "trash.fill",
                title: "Clear all data?",
                message:
                    "Permanently deletes your snapshots, mixtapes, listening history, "
                    + "and now-playing. Your profile, friends, and music-service "
                    + "pairings stay. This cannot be undone.",
                confirmTitle: "Clear data",
                cancelTitle: "Keep data",
                isBusy: clearing,
                onCancel: { confirmClear = false },
                onConfirm: { Task { await clearAll() } }
            )
        }
        .sheet(isPresented: $confirmDelete) {
            HeartableDestructiveConfirmation(
                icon: "person.crop.circle.badge.xmark",
                title: "Delete account?",
                message:
                    "Permanently deletes your profile, friends, snapshots, mixtapes, "
                    + "folders, history, and this device's saved music-service "
                    + "pairings. You’ll be signed out. This cannot be undone.",
                confirmTitle: "Delete account",
                cancelTitle: "Keep account",
                isBusy: deleting,
                onCancel: { confirmDelete = false },
                onConfirm: { Task { await deleteAccount() } }
            )
        }
    }

    /// App marketing version + build number, e.g. "Heartable 1.0.0 (1)".
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Heartable \(version) (\(build))"
    }

    private var artworkCacheDescription: String {
        guard artworkCacheBytes > 0 else {
            return "Artwork and profile images · Empty"
        }
        return "Artwork and profile images · "
            + ByteCountFormatter.string(
                fromByteCount: artworkCacheBytes,
                countStyle: .file
            )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(Typography.semibold(12))
            .tracking(1)
            .foregroundStyle(theme.palette.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func updateArtworkCacheSize() async {
        artworkCacheBytes = await ArtworkImageCache.shared.byteCount()
    }

    private func clearArtworkCache() async {
        clearingArtworkCache = true
        await ArtworkImageCache.shared.clear()
        artworkCacheBytes = 0
        clearingArtworkCache = false
        banners.success("Artwork cache cleared.")
    }

    private func clearAll() async {
        guard !clearing, !deleting, !signingOut,
              let ownerID = auth.userID else { return }
        clearing = true
        defer {
            backupScheduler.resume()
            nowPlayingSync.resume()
            clearing = false
        }
        resultMessage = nil
        do {
            try await backupScheduler.suspendAndWait()
            try await nowPlayingSync.suspendAndWait()
            guard auth.userID == ownerID else { throw BackendError.notSignedIn }
            try await BackendAPI.shared.deleteAllUserData(userID: ownerID)
            guard auth.userID == ownerID else { throw BackendError.notSignedIn }
            await topTracks.invalidateHistory()
            guard auth.userID == ownerID else { throw BackendError.notSignedIn }
            await weeklyRecap.clear(ownerID: ownerID)
            guard auth.userID == ownerID else { throw BackendError.notSignedIn }
            await librarySession.removeClearedMusicData(ownerID: ownerID, playlistTracks: playlistTracks)
            guard auth.userID == ownerID else { throw BackendError.notSignedIn }
            skips.reset()
            NotificationCenter.default.post(name: .heartableMusicDataCleared, object: ownerID)
            resultIsError = false
            resultMessage = "All data cleared."
            confirmClear = false
            banners.success("All data cleared.")
        } catch {
            resultIsError = true
            resultMessage = error.localizedDescription
            banners.error("Couldn't clear data. Please try again.")
        }
    }

    private func deleteAccount() async {
        deleting = true
        resultMessage = nil
        do {
            // On success this signs out, so RootView swaps back to the auth gate.
            try await auth.deleteAccount()
        } catch {
            resultIsError = true
            resultMessage = error.localizedDescription
            deleting = false
            banners.error("Couldn’t delete account. Please try again.")
        }
    }
}
