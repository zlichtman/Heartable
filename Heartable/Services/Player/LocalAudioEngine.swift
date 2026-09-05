import Foundation
import AVFoundation
import Observation

/// Serializes the blocking `AVAudioSession` setup away from `MainActor`.
/// Activation is intentionally lazy so constructing the shared engine neither
/// stalls launch nor interrupts another app's audio before the user presses play.
private actor LocalPlaybackAudioSession {
    func activate() throws {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            throw ProviderError("Heartable couldn’t activate audio. Try playing the song again.")
        }
    }
}

/// In-app streaming engine for providers Heartable plays itself (Audius full
/// tracks, Deezer 30s previews). Spotify/Apple use their own system players.
/// `PlayerStore` reads `nowPlaying`/`isPlaying`/`positionMs`.
///
/// Two `AVPlayer`s back the engine so crossfade is real: at a track change the
/// outgoing track fades out on one player while the incoming track fades in on
/// the other. With crossfade off, only one player is ever audible. Audio prefs
/// come from `AudioSettings` (read live from the same `@AppStorage` keys
/// `SoundsView` writes), so the toggles in Settings take effect immediately.
@MainActor
@Observable
final class LocalAudioEngine {
    static let shared = LocalAudioEngine()

    struct NowPlaying: Equatable, Sendable {
        let key: String
        let providerID: ProviderID
        let uri: String
        let trackID: String
        let name: String
        let artist: String
        let artworkURL: URL?
        let durationMs: Int
    }

    private(set) var nowPlaying: NowPlaying?
    private(set) var isPlaying = false
    private(set) var positionMs = 0

    /// Two players so we can overlap two tracks during a crossfade. `active` is
    /// the one whose track is "now playing"; the other is idle or fading out.
    private let playerA = AVPlayer()
    private let playerB = AVPlayer()
    private var activeIsA = true
    private var active: AVPlayer { activeIsA ? playerA : playerB }
    private var idle: AVPlayer { activeIsA ? playerB : playerA }

    private var timeObservers: [Any] = []
    private var completionObserver: NSObjectProtocol?
    var onCompletion: (@MainActor (String) -> Void)?
    /// In-flight crossfade ramp; cancelled if the user acts mid-fade.
    private var fadeTask: Task<Void, Never>?
    private var fadeProgress: Float?
    private var settings = AudioSettings.current()
    /// Every start is awaited by its caller. A generation also invalidates a
    /// pending start when Pause/Stop is pressed during audio-session activation.
    private var startGeneration = UUID()
    private var isPreparing = false
    private let audioSession = LocalPlaybackAudioSession()

    private init() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        // Both players need observers: after a crossfade, the idle player's
        // clock stops and can no longer drive progress for the active player.
        for (index, player) in [playerA, playerB].enumerated() {
            let observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.activeIsA == (index == 0) else { return }
                    let seconds = self.active.currentTime().seconds
                    self.positionMs = seconds.isFinite ? Int(max(0, seconds) * 1000) : 0
                    self.isPlaying = self.active.timeControlStatus == .playing
                }
            }
            timeObservers.append(observer)
        }
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] notification in
            let finishedItemID = (notification.object as? AVPlayerItem).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let item = self.active.currentItem,
                      ObjectIdentifier(item) == finishedItemID, let track = self.nowPlaying else { return }
                self.isPlaying = false
                self.onCompletion?(track.uri)
            }
        }
    }

    func play(_ meta: NowPlaying, url: URL) async throws {
        try Task.checkCancellation()
        let generation = UUID()
        startGeneration = generation
        isPreparing = true
        defer { if startGeneration == generation { isPreparing = false } }
        do {
            // Other providers and interruptions can deactivate the shared
            // session. Never trust an activation cached from an earlier song.
            try await audioSession.activate()
            try Task.checkCancellation()
            guard startGeneration == generation else { throw CancellationError() }
            startPlayback(meta, url: url)
            try await waitForPlayback(generation: generation)
        } catch {
            if startGeneration == generation { pause() }
            throw error
        }
    }

    private func waitForPlayback(generation: UUID) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while true {
            try Task.checkCancellation()
            guard startGeneration == generation else { throw CancellationError() }
            if active.currentItem?.status == .failed {
                // AVFoundation errors may contain credential-bearing stream
                // URLs. Keep those out of notifications and logs.
                throw ProviderError("This stream couldn’t be played. Try another song or check the service connection.")
            }
            if active.timeControlStatus == .playing {
                isPlaying = true
                return
            }
            guard ContinuousClock.now < deadline else {
                throw ProviderError("This stream took too long to start. Check your connection and try again.")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func startPlayback(_ meta: NowPlaying, url: URL) {
        applySettings(AudioSettings.current())
        let target = settings.targetVolume

        // Crossfade only makes sense when something is already audibly playing and
        // the user has the pref on. Otherwise do a plain hard switch on the active
        // player (and cancel any fade still running).
        let shouldCrossfade = settings.crossfade
            && nowPlaying != nil
            && active.timeControlStatus == .playing

        settleFade()

        if shouldCrossfade {
            crossfade(to: meta, url: url, duration: settings.crossfadeDuration)
        } else {
            hardSwitch(to: meta, url: url, target: target)
        }
    }

    /// Plain switch: load into the active player at the target volume and play.
    private func hardSwitch(to meta: NowPlaying, url: URL, target: Float) {
        idle.pause() // make sure no leftover fade-out track keeps playing
        let item = AVPlayerItem(url: url)
        active.replaceCurrentItem(with: item)
        active.volume = target
        nowPlaying = meta
        positionMs = 0
        active.play()
        isPlaying = active.timeControlStatus == .playing
    }

    /// Overlap two players: incoming starts silent on the idle player and ramps up
    /// while the outgoing (currently active) player ramps down, then we swap.
    private func crossfade(to meta: NowPlaying, url: URL, duration: TimeInterval) {
        let outgoing = active
        let incoming = idle
        let item = AVPlayerItem(url: url)
        incoming.replaceCurrentItem(with: item)
        incoming.volume = 0
        incoming.play()

        // Swap which player is "active" up front so position/now-playing reflect
        // the incoming track immediately; the outgoing player keeps fading.
        activeIsA.toggle()
        fadeProgress = 0
        nowPlaying = meta
        positionMs = 0
        isPlaying = incoming.timeControlStatus == .playing

        // Inherits MainActor isolation, so touching the players and @Observable
        // state here is safe and stays on the main thread.
        fadeTask = Task { [weak self] in
            // Keep the outgoing song audible while the incoming stream buffers.
            // The awaited start owns timeout/error handling and cancels this task.
            while incoming.timeControlStatus != .playing {
                guard !Task.isCancelled else { return }
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
            let steps = 40
            let stepNanos = UInt64(duration / Double(steps) * 1_000_000_000)
            for i in 1...steps {
                guard !Task.isCancelled, let self else { return }
                self.fadeProgress = Float(i) / Float(steps)
                self.applyVolumes()
                try? await Task.sleep(nanoseconds: stepNanos)
            }
            guard !Task.isCancelled, let self else { return }
            self.fadeProgress = nil
            incoming.volume = self.settings.targetVolume
            outgoing.volume = 0
            outgoing.pause()
            outgoing.replaceCurrentItem(with: nil)
            self.fadeTask = nil
        }
    }

    /// Settings apply while playing or paused, including both sides of a fade.
    /// Never touch the system output volume or a provider-owned player.
    func applySettings(_ settings: AudioSettings) {
        self.settings = settings
        if !settings.crossfade, fadeTask != nil { settleFade() }
        applyVolumes()
    }

    private func applyVolumes() {
        if let fadeProgress {
            let gains = settings.fadeVolumes(progress: fadeProgress)
            active.volume = gains.incoming
            idle.volume = gains.outgoing
        } else {
            active.volume = settings.targetVolume
            idle.volume = 0
        }
    }

    private func settleFade() {
        fadeTask?.cancel()
        fadeTask = nil
        fadeProgress = nil
        idle.pause()
        idle.volume = 0
        idle.replaceCurrentItem(with: nil)
        active.volume = settings.targetVolume
    }

    func toggle() async throws {
        if isPreparing {
            pause()
            return
        }
        if active.timeControlStatus == .playing { pause() }
        else {
            let generation = UUID()
            startGeneration = generation
            isPreparing = true
            defer { if startGeneration == generation { isPreparing = false } }
            do {
                try await audioSession.activate()
                try Task.checkCancellation()
                guard startGeneration == generation else { throw CancellationError() }
                applySettings(AudioSettings.current())
                active.play()
                try await waitForPlayback(generation: generation)
            } catch {
                if startGeneration == generation { pause() }
                throw error
            }
        }
    }

    func pause() {
        startGeneration = UUID()
        isPreparing = false
        // Cancel any in-flight fade and quiet the idle/outgoing player too.
        settleFade()
        active.pause()
        idle.pause()
        isPlaying = false
    }

    func seek(toMs ms: Int) {
        active.seek(to: CMTime(seconds: Double(max(0, ms)) / 1000, preferredTimescale: 600))
        positionMs = ms
    }

    func stop() {
        startGeneration = UUID()
        isPreparing = false
        settleFade()
        playerA.pause()
        playerB.pause()
        playerA.replaceCurrentItem(with: nil)
        playerB.replaceCurrentItem(with: nil)
        nowPlaying = nil
        isPlaying = false
        positionMs = 0
    }

    func isCurrent(_ providerID: ProviderID) -> Bool {
        nowPlaying?.providerID == providerID
    }
}
