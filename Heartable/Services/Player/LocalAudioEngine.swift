import Foundation
import AVFoundation
import Observation

/// Serializes the blocking `AVAudioSession` setup away from `MainActor`.
/// Activation is intentionally lazy so constructing the shared engine neither
/// stalls launch nor interrupts another app's audio before the user presses play.
private actor LocalPlaybackAudioSession {
    private var isConfiguredAndActive = false

    func activate() -> Bool {
        if isConfiguredAndActive { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            isConfiguredAndActive = true
            return true
        } catch {
            // A later play request retries transient activation failures. AVPlayer
            // still gets a chance to play, matching the engine's prior fallback.
            return false
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
    /// A first play waits for background audio-session activation. Keeping the
    /// task lets pause/stop or a newer play cancel an obsolete deferred start.
    private var pendingPlayTask: Task<Void, Never>?
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

    func play(_ meta: NowPlaying, url: URL) {
        guard !Task.isCancelled else { return }
        pendingPlayTask?.cancel()
        pendingPlayTask = Task { [weak self, audioSession] in
            _ = await audioSession.activate()
            guard !Task.isCancelled, let self else { return }
            self.pendingPlayTask = nil
            self.startPlayback(meta, url: url)
        }
    }

    private func startPlayback(_ meta: NowPlaying, url: URL) {
        let settings = AudioSettings.current()
        let target = settings.targetVolume

        // Crossfade only makes sense when something is already audibly playing and
        // the user has the pref on. Otherwise do a plain hard switch on the active
        // player (and cancel any fade still running).
        let shouldCrossfade = settings.crossfade
            && nowPlaying != nil
            && active.timeControlStatus == .playing

        fadeTask?.cancel()
        fadeTask = nil

        if shouldCrossfade {
            crossfade(to: meta, url: url, target: target)
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
        isPlaying = true
    }

    /// Overlap two players: incoming starts silent on the idle player and ramps up
    /// while the outgoing (currently active) player ramps down, then we swap.
    private func crossfade(to meta: NowPlaying, url: URL, target: Float) {
        let outgoing = active
        let incoming = idle
        let item = AVPlayerItem(url: url)
        incoming.replaceCurrentItem(with: item)
        incoming.volume = 0
        incoming.play()

        // Swap which player is "active" up front so position/now-playing reflect
        // the incoming track immediately; the outgoing player keeps fading.
        activeIsA.toggle()
        nowPlaying = meta
        positionMs = 0
        isPlaying = true

        let duration = AudioSettings.crossfadeDuration
        let outStart = outgoing.volume

        // Inherits MainActor isolation, so touching the players and @Observable
        // state here is safe and stays on the main thread.
        fadeTask = Task { [weak self] in
            let steps = 40
            let stepNanos = UInt64(duration / Double(steps) * 1_000_000_000)
            for i in 1...steps {
                if Task.isCancelled { return }
                let t = Float(i) / Float(steps)
                incoming.volume = target * t
                outgoing.volume = outStart * (1 - t)
                try? await Task.sleep(nanoseconds: stepNanos)
            }
            if Task.isCancelled { return }
            incoming.volume = target
            outgoing.volume = 0
            outgoing.pause()
            outgoing.replaceCurrentItem(with: nil)
            self?.fadeTask = nil
        }
    }

    func toggle() {
        if pendingPlayTask != nil {
            pause()
            return
        }
        if active.timeControlStatus == .playing { pause() }
        else { active.play(); isPlaying = true }
    }

    func pause() {
        pendingPlayTask?.cancel()
        pendingPlayTask = nil
        // Cancel any in-flight fade and quiet the idle/outgoing player too.
        fadeTask?.cancel()
        fadeTask = nil
        active.pause()
        idle.pause()
        isPlaying = false
    }

    func seek(toMs ms: Int) {
        active.seek(to: CMTime(seconds: Double(max(0, ms)) / 1000, preferredTimescale: 600))
        positionMs = ms
    }

    func stop() {
        pendingPlayTask?.cancel()
        pendingPlayTask = nil
        fadeTask?.cancel()
        fadeTask = nil
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
