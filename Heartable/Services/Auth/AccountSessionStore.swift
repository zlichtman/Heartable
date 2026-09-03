import Foundation

/// Owns the boundary between a Heartable account and account-sensitive state kept
/// on this device. Provider credentials and connection preferences are namespaced
/// by the Heartable user UUID: signing out deactivates the namespace without
/// deleting it, while another account sees only its own paired services.
///
/// Device identity and appearance are deliberately not included here: Plex's
/// client identifier, Jellyfin's device identifier, the selected theme, and custom
/// themes belong to the installation rather than to a signed-in account.
enum AccountSessionStore {
    private static let ownerKey = "heartable.accountSession.owner"
    static let profileCacheKey = "heartable.profile.cache.v1"
    static let providerManifestCacheKey = "heartable.providerConnections.manifest.v1"

    /// Legacy unscoped provider and backup preferences migrated into the first
    /// known owner. Appearance remains device-level personalization.
    static let providerDefaultKeys = [
        "apple_music_disabled",
        "heartable.backup.frequency",
        "heartable.backups.lastRun",
        "heartable.audius.enabled",
        "heartable.deezer.enabled",
        "heartable.internetArchive.enabled",
        "heartable.jellyfin.server",
        "heartable.jellyfin.userId",
        "heartable.jellyfin.username",
        "heartable.lastfm.enabled",
        "heartable.lastfm.user",
        "heartable.listenbrainz.user",
        "heartable.mixcloud.enabled",
        "heartable.radioBrowser.enabled",
        providerManifestCacheKey,
    ] + ProviderID.allCases.map { "heartable.backup.service.\($0.rawValue)" }

    static let providerKeychainKeys = [
        "heartable_spotify_access",
        "heartable_spotify_refresh",
        "heartable_spotify_refresh_prev",
        "heartable_spotify_expiry",
        "heartable_plex_token",
        "heartable_jellyfin_token",
    ]

    static var currentOwnerID: UUID? {
        UserDefaults.standard.string(forKey: ownerKey).flatMap(UUID.init(uuidString:))
    }

    /// Deterministic namespace for provider state. The explicit owner overload is
    /// used by OAuth/refresh tasks so a late callback can never write into a newly
    /// active account.
    static func scopedKey(_ base: String, ownerID: UUID) -> String {
        "heartable.account.\(ownerID.uuidString.lowercased()).\(base)"
    }

    static func defaultObject(
        forKey key: String,
        ownerID: UUID? = currentOwnerID
    ) -> Any? {
        guard let ownerID else { return nil }
        return UserDefaults.standard.object(forKey: scopedKey(key, ownerID: ownerID))
    }

    static func defaultString(
        forKey key: String,
        ownerID: UUID? = currentOwnerID
    ) -> String? {
        defaultObject(forKey: key, ownerID: ownerID) as? String
    }

    static func defaultBool(
        forKey key: String,
        defaultValue: Bool = false,
        ownerID: UUID? = currentOwnerID
    ) -> Bool {
        defaultObject(forKey: key, ownerID: ownerID) as? Bool ?? defaultValue
    }

    static func setDefault(
        _ value: Any?,
        forKey key: String,
        ownerID: UUID? = currentOwnerID
    ) {
        guard let ownerID else { return }
        let scoped = scopedKey(key, ownerID: ownerID)
        if let value {
            UserDefaults.standard.set(value, forKey: scoped)
        } else {
            UserDefaults.standard.removeObject(forKey: scoped)
        }
    }

    static func removeDefault(
        forKey key: String,
        ownerID: UUID? = currentOwnerID
    ) {
        setDefault(nil, forKey: key, ownerID: ownerID)
    }

    static func keychainValue(
        forKey key: String,
        ownerID: UUID? = currentOwnerID
    ) -> String? {
        guard let ownerID else { return nil }
        return Keychain.get(scopedKey(key, ownerID: ownerID))
    }

    static func setKeychainValue(
        _ value: String?,
        forKey key: String,
        ownerID: UUID? = currentOwnerID
    ) {
        guard let ownerID else { return }
        Keychain.set(value, for: scopedKey(key, ownerID: ownerID))
    }

    static func deleteKeychainValue(
        forKey key: String,
        ownerID: UUID? = currentOwnerID
    ) {
        guard let ownerID else { return }
        Keychain.delete(scopedKey(key, ownerID: ownerID))
    }

    /// Reconcile restored auth with the active account namespace. Legacy global
    /// provider state is adopted exactly once by its known prior owner (or by the
    /// restored user on first upgrade) before the global keys are removed.
    @MainActor
    static func prepare(for userID: UUID?) async {
        let priorOwner = currentOwnerID

        if let legacyOwner = priorOwner ?? userID {
            migrateLegacyProviderState(
                to: legacyOwner,
                adoptingExistingOwner: priorOwner != nil
            )
        } else {
            clearOrphanedLegacyProviderState()
        }

        if let userID {
            UserDefaults.standard.set(userID.uuidString, forKey: ownerKey)
        } else {
            LocalAudioEngine.shared.stop()
            AppleMusicProvider.stopPlayback()
            UserDefaults.standard.removeObject(forKey: ownerKey)
        }
    }

    /// Permanently deletes one Heartable account's provider vault and caches.
    /// Used for account deletion only; normal sign-out deliberately does not call
    /// this. Explicit service disconnects delete just that provider's scoped keys.
    @MainActor
    static func clear(ownerID: UUID? = currentOwnerID) async {
        guard let ownerID else { return }
        let isActiveOwner = currentOwnerID == ownerID

        // These adapters own private Keychain keys and in-memory resolver/player
        // state, so use their disconnect paths when deleting the active account.
        if isActiveOwner {
            async let plex: Void = PlexProvider().disconnect()
            async let jellyfin: Void = JellyfinProvider().disconnect()
            async let apple: Void = AppleMusicProvider().disconnect()
            await SpotifyAuth.clearSession(ownerID: ownerID)
            _ = await (plex, jellyfin, apple)
        }
        LocalAudioEngine.shared.stop()

        let defaults = UserDefaults.standard
        for key in providerDefaultKeys {
            defaults.removeObject(forKey: scopedKey(key, ownerID: ownerID))
        }
        defaults.removeObject(forKey: scopedKey(profileCacheKey, ownerID: ownerID))
        for key in providerKeychainKeys {
            Keychain.delete(scopedKey(key, ownerID: ownerID))
        }
        defaults.removeObject(forKey: migrationMarker(ownerID))
        if isActiveOwner {
            defaults.removeObject(forKey: ownerKey)
        }

        removeLibraryCaches(ownerID: ownerID)
    }

    /// Stable per-account filename for caches that cannot accept an AuthStore
    /// dependency. Supplying `ownerID` makes the naming logic directly testable.
    static func scopedFilename(
        _ base: String,
        ext: String,
        ownerID: UUID? = currentOwnerID
    ) -> String {
        let owner = ownerID?.uuidString.lowercased() ?? "unowned"
        return "\(base)-\(owner).\(ext)"
    }

    private static func migrationMarker(_ ownerID: UUID) -> String {
        scopedKey("provider-migration-v1", ownerID: ownerID)
    }

    private static func migrateLegacyProviderState(
        to ownerID: UUID,
        adoptingExistingOwner: Bool
    ) {
        let defaults = UserDefaults.standard
        let marker = migrationMarker(ownerID)
        guard !defaults.bool(forKey: marker) else { return }

        for key in providerDefaultKeys {
            let destination = scopedKey(key, ownerID: ownerID)
            if defaults.object(forKey: destination) == nil,
               let legacy = defaults.object(forKey: key) {
                defaults.set(legacy, forKey: destination)
            }
            defaults.removeObject(forKey: key)
        }
        // Older releases treated a missing switch as connected once MusicKit was
        // authorized. Preserve that behavior only for the already-known owner
        // being upgraded; a genuinely new Heartable account starts disconnected.
        let appleDestination = scopedKey("apple_music_disabled", ownerID: ownerID)
        if adoptingExistingOwner,
           defaults.object(forKey: appleDestination) == nil {
            defaults.set(false, forKey: appleDestination)
        }
        for key in providerKeychainKeys {
            let destination = scopedKey(key, ownerID: ownerID)
            if Keychain.get(destination) == nil, let legacy = Keychain.get(key) {
                Keychain.set(legacy, for: destination)
            }
            Keychain.delete(key)
        }
        migrateLegacyCaches(to: ownerID)
        defaults.set(true, forKey: marker)
    }

    private static func clearOrphanedLegacyProviderState() {
        let defaults = UserDefaults.standard
        for key in providerDefaultKeys {
            defaults.removeObject(forKey: key)
        }
        for key in providerKeychainKeys {
            Keychain.delete(key)
        }
    }

    private static func migrateLegacyCaches(to ownerID: UUID) {
        let fm = FileManager.default
        let destinations: [(URL?, String)] = [
            (
                fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
                "heartable-library-cache"
            ),
            (
                fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                    .appendingPathComponent("Heartable", isDirectory: true),
                "master-library"
            ),
            (
                fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                    .appendingPathComponent("Heartable", isDirectory: true),
                "playlist-tracks"
            ),
        ]
        for (directory, base) in destinations {
            guard let directory else { continue }
            let legacy = directory.appendingPathComponent("\(base).json")
            let scoped = directory.appendingPathComponent(
                scopedFilename(base, ext: "json", ownerID: ownerID)
            )
            guard fm.fileExists(atPath: legacy.path) else { continue }
            if fm.fileExists(atPath: scoped.path) {
                // Never leave unscoped account data available for a later account
                // to adopt after this owner's migration is marked complete.
                try? fm.removeItem(at: legacy)
            } else {
                try? fm.moveItem(at: legacy, to: scoped)
            }
        }
    }

    private static func removeLibraryCaches(ownerID: UUID) {
        let fm = FileManager.default
        let owner = ownerID.uuidString.lowercased()

        if let cacheDirectory = fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let files = try? fm.contentsOfDirectory(
               at: cacheDirectory,
               includingPropertiesForKeys: nil
           ) {
            for file in files where
                file.lastPathComponent == "heartable-library-cache-\(owner).json" {
                try? fm.removeItem(at: file)
            }
        }

        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Heartable", isDirectory: true),
           let files = try? fm.contentsOfDirectory(
               at: appSupport,
               includingPropertiesForKeys: nil
           ) {
            for file in files where
                file.lastPathComponent == "master-library-\(owner).json"
                || file.lastPathComponent == "playlist-tracks-\(owner).json"
                || (
                    file.lastPathComponent.hasPrefix("top-tracks-")
                        && file.lastPathComponent.contains(owner)
                ) {
                try? fm.removeItem(at: file)
            }
        }
    }
}
