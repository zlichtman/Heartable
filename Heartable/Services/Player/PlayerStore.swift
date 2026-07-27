import Foundation
import Observation
import MusicKit

/// Keeps a last-known Spotify state through a short run of transport failures
/// without allowing that state to live forever. A successful or authoritative
/// idle poll resets the window; repeated failures do not extend it.
struct SpotifyFailureRetentionWindow {
    static let defaultGrace: TimeInterval = 30

    private(set) var expiresAt: Date?

    mutating func shouldRetain(
        at now: Date,
        grace: TimeInterval = defaultGrace
    ) -> Bool {
        if let expiresAt {
            return now < expiresAt
        }
        expiresAt = now.addingTimeInterval(grace)
        return true
    }

    mutating func extend(through date: Date) {
        if let current = expiresAt {
            if current < date {
                expiresAt = date
            }
        } else {
            expiresAt = date
        }
    }

    mutating func reset() {
        expiresAt = nil
    }
}

/// Selects only an exact cross-provider identity so a Spotify device failure can
/// fall back to playback inside Heartable without ever starting the wrong song.
struct PlaybackFallbackSelector {
    static func bestAlternative(
        for original: UnifiedTrack,
        from candidates: [UnifiedTrack]
    ) -> UnifiedTrack? {
        let identity = UnifiedTrackIdentity.make(
            title: original.name,
            artist: original.artists.first?.name ?? ""
        )
        let catalogOrder = Dictionary(
            uniqueKeysWithValues: ProviderCatalog.all.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )

        return candidates
            .filter { candidate in
                guard candidate.providerID != .spotify,
                      candidate.providerID == .apple || candidate.providerID.playsViaLocalEngine,
                      ProviderPlayback.isPlayable(candidate.providerID) else {
                    return false
                }
                return UnifiedTrackIdentity.make(
                    title: candidate.name,
                    artist: candidate.artists.first?.name ?? ""
                ) == identity
            }
            .sorted { lhs, rhs in
                let lhsTier = ProviderPlayback.tier(for: lhs.providerID)
                let rhsTier = ProviderPlayback.tier(for: rhs.providerID)
                if lhsTier != rhsTier { return lhsTier > rhsTier }

                let lhsDurationDelta = durationDelta(lhs, original)
                let rhsDurationDelta = durationDelta(rhs, original)
                if lhsDurationDelta != rhsDurationDelta {
                    return lhsDurationDelta < rhsDurationDelta
                }

                return (catalogOrder[lhs.providerID] ?? .max)
                    < (catalogOrder[rhs.providerID] ?? .max)
            }
            .first
    }

    private static func durationDelta(
        _ candidate: UnifiedTrack,
        _ original: UnifiedTrack
    ) -> Int {
        guard candidate.durationMs > 0, original.durationMs > 0 else {
            return .max
        }
        return abs(candidate.durationMs - original.durationMs)
    }
}

/// Unified now-playing across the three playback sources — Spotify (Web API
/// poll), Apple Music (MusicKit state), and the in-app engine (Audius/Deezer).
/// Picks the most-recently-changed *playing* source so tapping a song on any
/// service takes over the player. Ported from the RN PlayerContext.
@MainActor
@Observable
final class PlayerStore {
    struct Now: Equatable, Sendable {
        var source: ProviderID
        var name: String
        var artist: String
        var artworkURL: URL?
        var isPlaying: Bool
        var positionMs: Int
        var durationMs: Int
        var uri: String
        var providerTrackID: String
    }

    private(set) var now: Now?
    private var lastConfirmedNow: Now?
    private(set) var feedbackMessage: String?
    private(set) var feedbackID = UUID()
    private(set) var startingTrackKey: String?
    var hasTrack: Bool { now != nil }

    private var pollTask: Task<Void, Never>?
    private var lastKey: [ProviderID: String] = [:]
    private var changedAt: [ProviderID: Date] = [:]
    private var tick = 0
    /// When set, Spotify returned 429 — skip Spotify polls until this time.
    private var spotifyBackoffUntil: Date?
    private var spotifyFailureRetention = SpotifyFailureRetentionWindow()
    private var pendingSpotifyTrack: UnifiedTrack?
    private var playRequestID = UUID()
    private var playbackStartTask: Task<Void, Never>?
    private var pendingStartTrack: UnifiedTrack?
    private var pendingStartExpiresAt: Date?

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = await self?.refresh() ?? 8
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stop() { pollTask?.cancel(); pollTask = nil }

    /// Stop polling and forget the now-playing track + recency state (call on
    /// sign-out / delete / account switch so the mini-player doesn't linger).
    func reset() {
        stop()
        now = nil
        lastConfirmedNow = nil
        lastKey = [:]
        changedAt = [:]
        spotifyBackoffUntil = nil
        spotifyFailureRetention.reset()
        pendingSpotifyTrack = nil
        playRequestID = UUID()
        playbackStartTask?.cancel()
        playbackStartTask = nil
        pendingStartTrack = nil
        pendingStartExpiresAt = nil
        startingTrackKey = nil
        feedbackMessage = nil
    }

    /// Refreshes the unified now-playing and returns how long to wait before the
    /// next poll. The cadence is adaptive to keep Spotify's Web API well under its
    /// rate limit: fast only while actively playing, slow when paused/idle, and
    /// Spotify itself is only polled when it's the active source (or occasionally,
    /// to catch a takeover) — never every cycle when another source is in control.
    @discardableResult
    func refresh() async -> Double {
        tick &+= 1
        var candidates: [Now] = []
        let previousNow = now

        // In-app engine (fully under our control).
        let engine = LocalAudioEngine.shared
        if let l = engine.nowPlaying {
            candidates.append(Now(
                source: l.providerID, name: l.name, artist: l.artist,
                artworkURL: l.artworkURL, isPlaying: engine.isPlaying,
                positionMs: engine.positionMs, durationMs: l.durationMs,
                uri: l.uri, providerTrackID: l.trackID
            ))
        }

        // Spotify (Web API poll) — gated to spare the rate limit. A failed poll,
        // token-refresh race, or active 429 backoff is not evidence that playback
        // ended: retain the last known Spotify state so the mini/full player does
        // not disappear. Only Spotify's authoritative idle response clears it.
        if shouldPollSpotify() {
            if let token = await SpotifyAuth.getValidAccessToken() {
                switch await SpotifyAPI.pollPlayback(token: token) {
                case .rateLimited(let retry):
                    let until = Date().addingTimeInterval(max(retry, 3))
                    spotifyBackoffUntil = until
                    // Keep the state until the server permits the next poll plus
                    // one grace window; another 429 may extend this explicitly.
                    spotifyFailureRetention.extend(
                        through: until.addingTimeInterval(
                            SpotifyFailureRetentionWindow.defaultGrace
                        )
                    )
                    retainPreviousSpotify(previousNow, in: &candidates)
                case .state(let state):
                    spotifyBackoffUntil = nil
                    spotifyFailureRetention.reset()
                    if let item = state.item {
                        let artURL = item.album?.images?.first?.url.flatMap { URL(string: $0) }
                        candidates.append(Now(
                            source: .spotify, name: item.name,
                            artist: item.artists?.first?.name ?? "",
                            artworkURL: artURL,
                            isPlaying: state.isPlaying ?? false,
                            positionMs: state.progressMs ?? 0,
                            durationMs: item.durationMs ?? 0,
                            uri: item.uri, providerTrackID: item.id
                        ))
                    }
                case .idle:
                    spotifyBackoffUntil = nil
                    spotifyFailureRetention.reset()
                case .failed:
                    retainPreviousSpotify(previousNow, in: &candidates)
                }
            } else if SpotifyAuth.isSignedIn {
                retainPreviousSpotify(previousNow, in: &candidates)
            } else {
                spotifyFailureRetention.reset()
            }
        } else if SpotifyAuth.isSignedIn {
            // The poll is intentionally paused while a 429 backoff is active.
            retainPreviousSpotify(previousNow, in: &candidates)
        } else {
            spotifyBackoffUntil = nil
            spotifyFailureRetention.reset()
        }

        // Apple Music (MusicKit). Best-effort read of the application player.
        if MusicAuthorization.currentStatus == .authorized,
           let entry = ApplicationMusicPlayer.shared.queue.currentEntry {
            let playing = ApplicationMusicPlayer.shared.state.playbackStatus == .playing
            candidates.append(Now(
                source: .apple, name: entry.title,
                artist: entry.subtitle ?? "",
                artworkURL: entry.artwork?.url(width: 600, height: 600),
                isPlaying: playing,
                positionMs: Int(ApplicationMusicPlayer.shared.playbackTime * 1000),
                durationMs: 0,
                uri: "apple:entry:\(entry.id)",
                providerTrackID: String(describing: entry.id)
            ))
        }
        let observedCandidates = candidates

        // A Spotify selection can be waiting for Connect to expose a device.
        // Keep that explicit user choice as the paused candidate instead of
        // letting an old paused Apple queue unexpectedly retake the mini-player.
        if let pendingSpotifyTrack,
           !candidates.contains(where: { $0.source == .spotify }) {
            var pending = Self.optimisticNow(pendingSpotifyTrack)
            pending.isPlaying = false
            candidates.append(pending)
        }

        if let pendingStartTrack,
           let pendingStartExpiresAt,
           Date() < pendingStartExpiresAt {
            let targetObserved = candidates.contains {
                $0.source == pendingStartTrack.providerID
                    && $0.name.localizedCaseInsensitiveCompare(
                        pendingStartTrack.name
                    ) == .orderedSame
            }
            if targetObserved {
                self.pendingStartTrack = nil
                self.pendingStartExpiresAt = nil
            } else {
                candidates.append(Self.optimisticNow(pendingStartTrack))
            }
        } else {
            pendingStartTrack = nil
            pendingStartExpiresAt = nil
        }

        // Track-change recency per source.
        for c in candidates {
            let key = "\(c.source.rawValue):\(c.providerTrackID)"
            if lastKey[c.source] != key {
                lastKey[c.source] = key
                changedAt[c.source] = Date()
            }
        }

        let playing = candidates.filter(\.isPlaying)
        let pool = playing.isEmpty ? candidates : playing
        let selected = pool.max {
            (changedAt[$0.source] ?? .distantPast) < (changedAt[$1.source] ?? .distantPast)
        }
        now = selected
        if let selected,
           observedCandidates.contains(selected) {
            lastConfirmedNow = selected
        } else if selected == nil {
            lastConfirmedNow = nil
        }
        return nextDelay()
    }

    private func retainPreviousSpotify(_ previous: Now?, in candidates: inout [Now]) {
        guard let previous, previous.source == .spotify else { return }
        guard spotifyFailureRetention.shouldRetain(at: Date()) else { return }
        candidates.append(previous)
    }

    /// Poll Spotify when it's the active source (keep it responsive); otherwise
    /// only occasionally, to notice a takeover — and never while backing off a 429.
    private func shouldPollSpotify() -> Bool {
        if let until = spotifyBackoffUntil, Date() < until { return false }
        switch now?.source {
        case .spotify: return true
        case nil: return true               // startup must discover Spotify immediately
        default: return tick % 4 == 0       // another source active: occasional check
        }
    }

    /// Responsive while playing, relaxed when paused/idle. Honors an active 429
    /// backoff so we don't spin tight against the limit.
    private func nextDelay() -> Double {
        if let until = spotifyBackoffUntil, Date() < until {
            return max(3, until.timeIntervalSinceNow)
        }
        guard let now else { return 8 }
        return now.isPlaying ? 3 : 8
    }

    // MARK: Start playback

    func play(_ track: UnifiedTrack) async {
        playbackStartTask?.cancel()
        let requestID = UUID()
        playRequestID = requestID
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performPlay(track, requestID: requestID)
        }
        playbackStartTask = task
        await task.value
        if playRequestID == requestID {
            playbackStartTask = nil
        }
    }

    private func performPlay(_ track: UnifiedTrack, requestID: UUID) async {
        let previous = lastConfirmedNow
        // A prior no-device request must never be started after the user has
        // already chosen a different song.
        pendingSpotifyTrack = nil
        startingTrackKey = track.key
        feedbackMessage = nil
        now = Self.optimisticNow(track)
        pendingStartTrack = track
        pendingStartExpiresAt = Date().addingTimeInterval(5)

        // Cross-source exclusivity: silence whatever else is playing before starting
        // the new track, so tapping an Apple Music song stops the Spotify Connect
        // device (and vice-versa) instead of both playing at once.
        await pauseOthers(except: track.providerID)
        guard playRequestID == requestID, !Task.isCancelled else { return }
        do {
            try await ProviderRegistry.playUnified(track)
            guard playRequestID == requestID, !Task.isCancelled else {
                if now?.source != track.providerID {
                    await pauseSource(track.providerID)
                }
                return
            }
            pendingSpotifyTrack = nil
            await refresh()
            guard playRequestID == requestID, !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard playRequestID == requestID, !Task.isCancelled else { return }
            await refresh()
        } catch is NoActiveDeviceError {
            guard playRequestID == requestID, !Task.isCancelled else { return }
            if let fallback = await alternateInAppSource(for: track) {
                guard playRequestID == requestID, !Task.isCancelled else { return }
                do {
                    pendingStartTrack = fallback
                    pendingStartExpiresAt = Date().addingTimeInterval(5)
                    await pauseOthers(except: fallback.providerID)
                    try await ProviderRegistry.playUnified(fallback)
                    guard playRequestID == requestID, !Task.isCancelled else { return }
                    pendingSpotifyTrack = nil
                    await refresh()
                    showFeedback(
                        "Spotify had no available device. Playing from "
                            + "\(Self.providerName(fallback.providerID)) instead."
                    )
                } catch {
                    pendingStartTrack = nil
                    pendingStartExpiresAt = nil
                    await restorePreviousAfterFailedStart(previous)
                    showFeedback(error.localizedDescription)
                }
            } else {
                guard playRequestID == requestID else { return }
                // Keep the requested song visible and paused so it can be retried,
                // but never auto-present an empty device chooser.
                self.now?.isPlaying = false
                pendingStartTrack = nil
                pendingStartExpiresAt = nil
                pendingSpotifyTrack = track
                showFeedback(
                    "No Spotify Connect device is available yet. "
                        + "When one appears, tap this song again."
                )
            }
        } catch {
            guard playRequestID == requestID, !Task.isCancelled else { return }
            pendingStartTrack = nil
            pendingStartExpiresAt = nil
            await restorePreviousAfterFailedStart(previous)
            showFeedback(error.localizedDescription)
        }
        if playRequestID == requestID {
            startingTrackKey = nil
        }
    }

    /// Starts the pending Spotify selection on the device chosen in Heartable.
    /// Returns false without discarding the pending song so the user can retry.
    func startPendingSpotify(on deviceID: String) async -> Bool {
        guard let track = pendingSpotifyTrack,
              let token = await SpotifyAuth.getValidAccessToken() else {
            return false
        }
        do {
            try await SpotifyAPI.play(
                token: token,
                uris: [track.uri],
                deviceId: deviceID
            )
            pendingSpotifyTrack = nil
            now = Self.optimisticNow(track)
            await refresh()
            return true
        } catch {
            showFeedback(error.localizedDescription)
            return false
        }
    }

    private func alternateInAppSource(for track: UnifiedTrack) async -> UnifiedTrack? {
        let identity = UnifiedTrackIdentity.make(
            title: track.name,
            artist: track.artists.first?.name ?? ""
        )
        if let cachedSources = MasterLibrarySnapshot.load()?
            .tracks.first(where: { $0.identity == identity })?
            .playableSources(),
           let cached = PlaybackFallbackSelector.bestAlternative(
                for: track,
                from: cachedSources
           ) {
            return cached
        }

        // The exact match may not be in the hydrated library yet. Search every
        // connected in-app playback provider once before asking for a Spotify
        // Connect device. Results are applied atomically to avoid UI churn.
        let providers = await ProviderRegistry.connected().filter { provider in
            guard provider.id != .spotify,
                  provider.id == .apple || provider.id.playsViaLocalEngine,
                  let entry = ProviderCatalog.entry(provider.id) else {
                return false
            }
            return entry.capabilities.contains([.search, .playback])
        }
        guard !providers.isEmpty else { return nil }

        let query = [track.name, track.artists.first?.name]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let searched = await withTaskGroup(
            of: [UnifiedTrack].self,
            returning: [UnifiedTrack].self
        ) { group in
            for provider in providers {
                group.addTask { await provider.search(query) }
            }
            var collected: [UnifiedTrack] = []
            for await result in group {
                collected.append(contentsOf: result)
            }
            return collected
        }
        return PlaybackFallbackSelector.bestAlternative(for: track, from: searched)
    }

    private func showFeedback(_ message: String) {
        feedbackMessage = message
        feedbackID = UUID()
    }

    private func restorePreviousAfterFailedStart(_ previous: Now?) async {
        guard let previous else {
            now = nil
            return
        }
        guard previous.isPlaying else {
            now = previous
            return
        }
        switch previous.source {
        case .apple:
            try? await ApplicationMusicPlayer.shared.play()
        case .spotify:
            if let token = await SpotifyAuth.getValidAccessToken() {
                await SpotifyAPI.resume(token: token)
            }
        default:
            if previous.source.playsViaLocalEngine,
               !LocalAudioEngine.shared.isPlaying {
                LocalAudioEngine.shared.toggle()
            }
        }
        await refresh()
        if now == nil {
            var paused = previous
            paused.isPlaying = false
            now = paused
        }
    }

    private func pauseSource(_ source: ProviderID) async {
        switch source {
        case .apple:
            ApplicationMusicPlayer.shared.pause()
        case .spotify:
            if let token = await SpotifyAuth.getValidAccessToken() {
                await SpotifyAPI.pause(token: token)
            }
        default:
            if source.playsViaLocalEngine {
                LocalAudioEngine.shared.pause()
            }
        }
    }

    private static func providerName(_ id: ProviderID) -> String {
        ProviderCatalog.entry(id)?.label ?? id.rawValue
    }

    private static func optimisticNow(_ track: UnifiedTrack) -> Now {
        Now(
            source: track.providerID,
            name: track.name,
            artist: track.artistNames,
            artworkURL: track.albumArt,
            isPlaying: true,
            positionMs: 0,
            durationMs: track.durationMs,
            uri: track.uri,
            providerTrackID: track.providerTrackID
        )
    }

    /// Pause every playback source except the one we're about to play on.
    /// Note: each ecosystem only controls its own output. Pausing Spotify here
    /// halts the active Spotify Connect device (e.g. your computer); Apple Music
    /// and the in-app engine always play on this device (route them elsewhere with
    /// AirPlay). There is no way to make Apple Music play *on* a Spotify device.
    private func pauseOthers(except keep: ProviderID) async {
        if keep != .spotify, let token = await SpotifyAuth.getValidAccessToken() {
            await SpotifyAPI.pause(token: token)
        }
        if keep != .apple, MusicAuthorization.currentStatus == .authorized {
            ApplicationMusicPlayer.shared.pause()
        }
        if !keep.playsViaLocalEngine {
            LocalAudioEngine.shared.pause()
        }
    }

    // MARK: Transport (routes to the active source)

    /// Every in-app streaming source (Audius/Deezer/Internet Archive/Radio
    /// Browser/Plex/Jellyfin) routes through the local engine; only Apple and
    /// Spotify have their own transports. Routing by `playsViaLocalEngine`
    /// (not an enumerated case list) keeps new in-app providers from silently
    /// falling through to the Spotify branch.
    func toggle() async {
        guard let now else { return }
        if now.source.playsViaLocalEngine {
            LocalAudioEngine.shared.toggle()
        } else if now.source == .apple {
            if now.isPlaying { ApplicationMusicPlayer.shared.pause() }
            else { try? await ApplicationMusicPlayer.shared.play() }
        } else if let token = await SpotifyAuth.getValidAccessToken() {
            if now.isPlaying { await SpotifyAPI.pause(token: token) }
            else { await SpotifyAPI.resume(token: token) }
        }
        await refresh()
    }

    func next() async {
        guard let now else { return }
        if now.source.playsViaLocalEngine {
            // Single-track engine: nothing queued to skip to.
        } else if now.source == .apple {
            try? await ApplicationMusicPlayer.shared.skipToNextEntry()
        } else if let token = await SpotifyAuth.getValidAccessToken() {
            await SpotifyAPI.next(token: token)
        }
        await refresh()
    }

    func prev() async {
        guard let now else { return }
        if now.source.playsViaLocalEngine {
            LocalAudioEngine.shared.seek(toMs: 0)
        } else if now.source == .apple {
            try? await ApplicationMusicPlayer.shared.skipToPreviousEntry()
        } else if let token = await SpotifyAuth.getValidAccessToken() {
            await SpotifyAPI.previous(token: token)
        }
        await refresh()
    }

    func seek(toMs ms: Int) async {
        guard let now else { return }
        if now.source.playsViaLocalEngine {
            LocalAudioEngine.shared.seek(toMs: ms)
        } else if now.source == .apple {
            ApplicationMusicPlayer.shared.playbackTime = Double(ms) / 1000
        } else if let token = await SpotifyAuth.getValidAccessToken() {
            await SpotifyAPI.seek(token: token, positionMs: ms)
        }
        // Reflect the target immediately so the scrubber doesn't rubber-band
        // back to the pre-seek position while the next poll catches up
        // (Spotify's playback state lags a seek by a beat).
        self.now?.positionMs = ms
    }
}
