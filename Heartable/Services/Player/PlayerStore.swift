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
    var hasPendingSpotify: Bool { pendingSpotifyTrack != nil }

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
    private var lifecycleID = UUID()
    private var queue = PlaybackQueue()
    private var lastAppleEntryID: String?
    private var lastObservationAt = Date()
    private var userPaused = false
    private var needsPlaybackRetry = false
    private var queueNeedsInstall = false

    func start() {
        guard pollTask == nil else { return }
        LocalAudioEngine.shared.onCompletion = { [weak self] uri in
            guard let self, startingTrackKey == nil, queue.current?.uri == uri, queue.hasNext else { return }
            let request = playRequestID
            Task {
                guard self.playRequestID == request else { return }
                await self.next()
            }
        }
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
        lifecycleID = UUID()
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
        queue = PlaybackQueue()
        lastAppleEntryID = nil
        userPaused = false
        needsPlaybackRetry = false
        queueNeedsInstall = false
        SpotifyAppRemote.shared.reset()
        AppleMusicQueue.reset()
        LocalAudioEngine.shared.onCompletion = nil
    }

    /// Refreshes the unified now-playing and returns how long to wait before the
    /// next poll. The cadence is adaptive to keep Spotify's Web API well under its
    /// rate limit: fast only while actively playing, slow when paused/idle, and
    /// Spotify itself is only polled when it's the active source (or occasionally,
    /// to catch a takeover) — never every cycle when another source is in control.
    @discardableResult
    func refresh() async -> Double {
        let requestID = lifecycleID
        let playbackRevision = playRequestID
        tick &+= 1
        var candidates: [Now] = []
        let previousNow = now
        let previousAppleEntryID = lastAppleEntryID
        let elapsed = Date().timeIntervalSince(lastObservationAt)
        var spotifyIdle = false

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
                guard lifecycleID == requestID, playRequestID == playbackRevision else { return 3 }
                let playback = await SpotifyAPI.pollPlayback(token: token)
                guard lifecycleID == requestID, playRequestID == playbackRevision else { return 3 }
                switch playback {
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
                    spotifyIdle = true
                    spotifyBackoffUntil = nil
                    spotifyFailureRetention.reset()
                case .failed:
                    retainPreviousSpotify(previousNow, in: &candidates)
                }
            } else if SpotifyAuth.isSignedIn {
                guard lifecycleID == requestID else { return 8 }
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
        guard lifecycleID == requestID, playRequestID == playbackRevision else { return 3 }

        // Apple Music (MusicKit). Best-effort read of the application player.
        if MusicAuthorization.currentStatus == .authorized,
           let entry = ApplicationMusicPlayer.shared.queue.currentEntry {
            let playing = ApplicationMusicPlayer.shared.state.playbackStatus == .playing
            var metadata = AppleMusicQueue.track(for: entry.id)
            if metadata == nil, case .song(let song) = entry.item {
                metadata = AppleMusicProvider.mapSong(song)
            }
            if let metadata {
                var apple = Self.optimisticNow(metadata)
                apple.isPlaying = playing
                apple.positionMs = Int(max(0, ApplicationMusicPlayer.shared.playbackTime) * 1000)
                apple.artworkURL = metadata.albumArt ?? entry.artwork?.url(width: 600, height: 600)
                candidates.append(apple)
            }
            lastAppleEntryID = entry.id
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

        var preferredTrack = pendingSpotifyTrack
        if let pendingStartTrack,
           let pendingStartExpiresAt,
           Date() < pendingStartExpiresAt {
            preferredTrack = pendingStartTrack
            let targetObserved = candidates.contains {
                $0.source == pendingStartTrack.providerID && $0.uri == pendingStartTrack.uri
                    && ($0.isPlaying || userPaused)
            }
            if targetObserved {
                self.pendingStartTrack = nil
                self.pendingStartExpiresAt = nil
            } else if !candidates.contains(where: {
                $0.source == pendingStartTrack.providerID && $0.uri == pendingStartTrack.uri
            }) {
                var pending = Self.optimisticNow(pendingStartTrack)
                pending.isPlaying = false
                candidates.append(pending)
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

        let selected = Self.selectCandidate(candidates, preferredTrack: preferredTrack, changedAt: changedAt)
        guard lifecycleID == requestID else { return 8 }
        now = selected
        if let selected,
           observedCandidates.contains(selected) {
            lastConfirmedNow = selected
            let newAppleOccurrence = selected.source == .apple
                && previousAppleEntryID != nil && previousAppleEntryID != lastAppleEntryID
            let newSpotifyOccurrence = selected.source == .spotify
                && previousNow?.uri == selected.uri && selected.positionMs < 2_000
                && (previousNow?.positionMs ?? 0) > max(5_000, selected.durationMs - 5_000)
            queue.observe(uri: selected.uri, newOccurrence: startingTrackKey == nil && (newAppleOccurrence || newSpotifyOccurrence))
        } else if selected == nil {
            lastConfirmedNow = nil
        }
        lastObservationAt = Date()
        // Native queues play through within one provider, even in the background.
        // When a mixed queue reaches its boundary, advance only on an end signal,
        // never on a normal pause or a transient polling error.
        if startingTrackKey == nil, !userPaused, queue.hasNext,
           let previousNow, previousNow.isPlaying,
           previousNow.uri == queue.current?.uri,
           previousNow.durationMs > 0,
           Double(previousNow.positionMs) + min(elapsed, 10) * 1_000 >= Double(previousNow.durationMs - 500),
           (previousNow.source == .spotify && spotifyIdle)
            || (previousNow.source == .apple && ApplicationMusicPlayer.shared.state.playbackStatus == .stopped) {
            Task { [weak self] in
                guard let self, self.playRequestID == playbackRevision else { return }
                await self.next()
            }
        }
        return nextDelay()
    }

    private func retainPreviousSpotify(_ previous: Now?, in candidates: inout [Now]) {
        guard let previous, previous.source == .spotify else { return }
        guard spotifyFailureRetention.shouldRetain(at: Date()) else { return }
        candidates.append(previous)
    }

    /// An explicit start owns the player while its transport is preparing. A
    /// delayed poll from the old provider must not steal the selected song.
    static func selectCandidate(_ candidates: [Now], preferredTrack: UnifiedTrack?,
                                changedAt: [ProviderID: Date]) -> Now? {
        if let preferredTrack,
           let selected = candidates.first(where: {
               $0.source == preferredTrack.providerID && $0.uri == preferredTrack.uri
           }) { return selected }
        let playing = candidates.filter(\.isPlaying)
        let pool = playing.isEmpty ? candidates : playing
        return pool.max {
            (changedAt[$0.source] ?? .distantPast) < (changedAt[$1.source] ?? .distantPast)
        }
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
        await play(tracks: [track])
    }

    func play(tracks: [UnifiedTrack], startingAt: Int? = nil,
              mode: ShuffleMode = .order, weights: [String: Int] = [:]) async {
        queue = PlaybackQueue(tracks: tracks, startingAt: startingAt, mode: mode, weights: weights)
        guard queue.current != nil else {
            showFeedback("These songs aren’t available for playback in Heartable.")
            return
        }
        await startQueue()
    }

    private func startQueue(positionMs: Int = 0, playing: Bool = true, wakeSpotify: Bool = false) async {
        guard let track = queue.current else { return }
        userPaused = !playing
        let previousStart = playbackStartTask
        previousStart?.cancel()
        let requestID = UUID()
        playRequestID = requestID
        let segment = queue.providerSegment
        let task = Task { [weak self] in
            guard let self else { return }
            // Finish cancellation before issuing new transport commands. This
            // prevents an older provider switch from pausing the newer song.
            await previousStart?.value
            guard playRequestID == requestID, !Task.isCancelled else { return }
            await performPlay(track, segment: segment, positionMs: positionMs,
                              playing: playing, wakeSpotify: wakeSpotify, requestID: requestID)
        }
        playbackStartTask = task
        await task.value
        if playRequestID == requestID { playbackStartTask = nil }
    }

    private func performPlay(_ track: UnifiedTrack, segment: [UnifiedTrack],
                             positionMs: Int, playing: Bool, wakeSpotify: Bool, requestID: UUID) async {
        let outgoing = now
        pendingSpotifyTrack = nil
        startingTrackKey = track.key
        needsPlaybackRetry = false
        queueNeedsInstall = false
        feedbackMessage = nil
        var pending = Self.optimisticNow(track)
        pending.isPlaying = false
        pending.positionMs = positionMs
        now = pending
        pendingStartTrack = track
        pendingStartExpiresAt = Date().addingTimeInterval(95)
        changedAt[track.providerID] = Date()

        do {
            try await pauseOthers(except: track.providerID, outgoing: outgoing)
            try Task.checkCancellation()
            guard playRequestID == requestID else { return }
            switch track.providerID {
            case .spotify:
                guard let token = await SpotifyAuth.getValidAccessToken() else {
                    throw ProviderError("Reconnect Spotify in Music Services.")
                }
                do {
                    if wakeSpotify { throw NoActiveDeviceError() }
                    try await installSpotifyQueue(segment, token: token, positionMs: positionMs)
                } catch is NoActiveDeviceError {
                    // Spotify must wake its process through its supported app
                    // switch. The SDK starts the selected song and returns here;
                    // no manual Play action or empty device picker is needed.
                    try await SpotifyAppRemote.shared.wakeAndPlay(track)
                    try Task.checkCancellation()
                    // App Remote can play before Connect publishes the phone.
                    // Wait through that short propagation gap without reopening
                    // Spotify or showing an empty device picker.
                    try await PlaybackStartupRetry.waitForSpotifyDevice {
                        try await self.installSpotifyQueue(segment, token: token, positionMs: positionMs)
                    }
                }
                if !playing { try await SpotifyAPI.control("/me/player/pause", token: token) }
            case .apple:
                try await AppleMusicQueue.start(segment, positionMS: positionMs, playing: playing) { [weak self] message in
                    guard self?.playRequestID == requestID else { return }
                    self?.showFeedback(message)
                }
            default:
                try await ProviderRegistry.playUnified(track)
                try Task.checkCancellation()
                if positionMs > 0 { LocalAudioEngine.shared.seek(toMs: positionMs) }
                if !playing { LocalAudioEngine.shared.pause() }
            }
            guard playRequestID == requestID, !Task.isCancelled else { return }
            await refresh()
            try await Task.sleep(for: .milliseconds(600))
            guard playRequestID == requestID, !Task.isCancelled else { return }
            await refresh()
        } catch {
            guard playRequestID == requestID, !Task.isCancelled else { return }
            needsPlaybackRetry = true
            pendingStartTrack = nil
            pendingStartExpiresAt = nil
            pendingSpotifyTrack = track.providerID == .spotify ? track : nil
            var paused = Self.optimisticNow(track)
            paused.isPlaying = false
            now = paused
            showFeedback(error.localizedDescription)
        }
        if playRequestID == requestID { startingTrackKey = nil }
    }

    private func installSpotifyQueue(_ tracks: [UnifiedTrack], token: String,
                                     deviceID: String? = nil, positionMs: Int = 0) async throws {
        try await SpotifyAPI.play(token: token, uris: tracks.map(\.uri),
                                  deviceId: deviceID, positionMs: positionMs)
        // Heartable has already ordered the queue, including weighted shuffle.
        // Inherited Spotify shuffle/repeat must not reorder or loop that queue.
        do {
            try await SpotifyAPI.control("/me/player/shuffle?state=false", token: token)
            try await SpotifyAPI.control("/me/player/repeat?state=off", token: token)
        } catch {
            try Task.checkCancellation()
            showFeedback("Playback started, but Spotify couldn’t apply the queue order. Try the playback mode again.")
        }
    }

    func applyPlaybackMode(_ mode: ShuffleMode, weights: [String: Int]) async {
        guard let current = now, current.uri == queue.current?.uri else { return }
        queue.reorder(mode: mode, weights: weights)
        if !current.isPlaying, startingTrackKey == nil {
            // Spotify cannot replace a queue without starting playback. Defer
            // the native update until Play so choosing a mode never emits audio.
            queueNeedsInstall = true
            return
        }
        // Local streams advance from our queue; native players need their queue
        // replaced while retaining the current song's position and pause state.
        if current.source == .apple || current.source == .spotify {
            await startQueue(positionMs: current.positionMs, playing: current.isPlaying)
        }
    }

    /// Start the same queue on an explicitly chosen Spotify Connect device.
    func startSpotifyOnThisIPhone() async -> Bool {
        guard let current = now, current.source == .spotify else { return false }
        if queue.current?.uri != current.uri {
            queue = PlaybackQueue(tracks: [Self.track(from: current)])
        }
        await startQueue(positionMs: current.positionMs, wakeSpotify: true)
        return !needsPlaybackRetry && now?.source == .spotify
    }

    /// Retry a pending song without losing its Heartable queue.
    func startPendingSpotify(on deviceID: String) async -> Bool {
        guard let track = pendingSpotifyTrack,
              let token = await SpotifyAuth.getValidAccessToken() else { return false }
        let request = playRequestID
        do {
            let tracks = queue.current?.uri == track.uri ? queue.providerSegment : [track]
            try await installSpotifyQueue(tracks, token: token, deviceID: deviceID)
            guard request == playRequestID else { return false }
            pendingSpotifyTrack = nil
            await refresh()
            return true
        } catch {
            guard request == playRequestID else { return false }
            showFeedback(error.localizedDescription)
            return false
        }
    }

    private func showFeedback(_ message: String) {
        feedbackMessage = message
        feedbackID = UUID()
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
    private func pauseOthers(except keep: ProviderID, outgoing: Now?) async throws {
        try Task.checkCancellation()
        if keep != .apple { AppleMusicQueue.cancel() }
        // Within a confirmed provider queue there is no handoff. Avoid a remote
        // pause round-trip for every direct-stream song/crossfade.
        if keep != .spotify, outgoing?.source != keep || lastConfirmedNow?.source != keep {
            if let token = await SpotifyAuth.getValidAccessToken() {
                try Task.checkCancellation()
                do { try await SpotifyAPI.control("/me/player/pause", token: token) }
                catch is NoActiveDeviceError { /* Already idle. */ }
                catch {
                    try Task.checkCancellation()
                    throw ProviderError("Couldn’t pause Spotify, so the provider switch was stopped. Try again or pause Spotify first.")
                }
            } else if outgoing?.source == .spotify, outgoing?.isPlaying == true {
                throw ProviderError("Reconnect Spotify or pause it before switching music services.")
            }
        }
        try Task.checkCancellation()
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
        if startingTrackKey != nil {
            playbackStartTask?.cancel()
            SpotifyAppRemote.shared.reset()
            AppleMusicQueue.cancel()
            startingTrackKey = nil
            pendingStartTrack = nil
            pendingStartExpiresAt = nil
            playRequestID = UUID()
            userPaused = true
            if let source = now?.source { await pauseSelectedSource(source) }
            self.now?.isPlaying = false
            needsPlaybackRetry = true
            return
        }
        if needsPlaybackRetry || pendingSpotifyTrack != nil {
            await startQueue()
            return
        }
        if queueNeedsInstall, now?.isPlaying == false {
            await startQueue(positionMs: now?.positionMs ?? 0)
            return
        }
        guard let current = now else { return }
        userPaused = current.isPlaying
        let request = playRequestID
        do {
            if current.source.playsViaLocalEngine {
                try await LocalAudioEngine.shared.toggle()
            } else if current.source == .apple {
                if current.isPlaying { ApplicationMusicPlayer.shared.pause() }
                else { try await ApplicationMusicPlayer.shared.play() }
            } else {
                let token = try await spotifyToken()
                if current.isPlaying {
                    try await SpotifyAPI.control("/me/player/pause", token: token)
                } else {
                    do { try await SpotifyAPI.play(token: token) }
                    catch is NoActiveDeviceError {
                        let track = Self.track(from: current)
                        if queue.current?.uri != track.uri { queue = PlaybackQueue(tracks: [track]) }
                        await startQueue()
                        return
                    }
                }
            }
            guard playRequestID == request, now?.uri == current.uri else { return }
            self.now?.isPlaying.toggle()
            await refresh()
        } catch {
            guard playRequestID == request, now?.uri == current.uri else { return }
            userPaused = false
            if current.source.playsViaLocalEngine { needsPlaybackRetry = true }
            showFeedback(error.localizedDescription)
        }
    }

    func next() async {
        if let current = queue.current, now == nil || now?.uri == current.uri || startingTrackKey != nil {
            guard queue.hasNext else { return }
            queue.next()
            await startQueue()
            return
        }
        guard let current = now else { return }
        do {
            if current.source == .apple { try await ApplicationMusicPlayer.shared.skipToNextEntry() }
            else if current.source == .spotify {
                try await SpotifyAPI.control("/me/player/next", method: "POST", token: spotifyToken())
            }
            await refresh()
        } catch { showFeedback(error.localizedDescription) }
    }

    func prev() async {
        guard let current = now else { return }
        if current.uri == queue.current?.uri {
            if current.positionMs > 3_000 || !queue.hasPrevious { await seek(toMs: 0) }
            else { queue.previous(); await startQueue() }
            return
        }
        do {
            if current.source.playsViaLocalEngine { LocalAudioEngine.shared.seek(toMs: 0) }
            else if current.source == .apple { try await ApplicationMusicPlayer.shared.skipToPreviousEntry() }
            else {
                try await SpotifyAPI.control("/me/player/previous", method: "POST", token: spotifyToken())
            }
            await refresh()
        } catch { showFeedback(error.localizedDescription) }
    }

    func seek(toMs ms: Int) async {
        guard let current = now else { return }
        let position = max(0, current.durationMs > 0 ? min(ms, current.durationMs) : ms)
        do {
            if current.source.playsViaLocalEngine { LocalAudioEngine.shared.seek(toMs: position) }
            else if current.source == .apple {
                ApplicationMusicPlayer.shared.playbackTime = Double(position) / 1000
            } else {
                try await SpotifyAPI.control("/me/player/seek?position_ms=\(position)", token: spotifyToken())
            }
            guard now?.uri == current.uri else { return }
            self.now?.positionMs = position
        } catch { showFeedback(error.localizedDescription) }
    }

    private func pauseSelectedSource(_ source: ProviderID) async {
        if source == .apple { ApplicationMusicPlayer.shared.pause() }
        else if source.playsViaLocalEngine { LocalAudioEngine.shared.pause() }
        else if let token = await SpotifyAuth.getValidAccessToken() { await SpotifyAPI.pause(token: token) }
    }

    private func spotifyToken() async throws -> String {
        guard let token = await SpotifyAuth.getValidAccessToken() else {
            throw ProviderError("Reconnect Spotify in Music Services.")
        }
        return token
    }

    private static func track(from now: Now) -> UnifiedTrack {
        UnifiedTrack(key: trackKey(now.source, now.providerTrackID), providerID: now.source,
                     providerTrackID: now.providerTrackID, uri: now.uri, name: now.name,
                     artists: [UnifiedArtist(id: now.artist, name: now.artist)],
                     album: nil, albumArt: now.artworkURL, durationMs: now.durationMs)
    }
}
