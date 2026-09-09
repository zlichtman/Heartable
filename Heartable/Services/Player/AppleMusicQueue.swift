// MusicKit's queue predates Sendable annotations. Keep access in this
// MainActor-owned bridge; only one generation may append to a native queue.
@preconcurrency import MusicKit
import Foundation

@MainActor
enum AppleMusicQueue {
    private static var fillTask: Task<Void, Never>?
    private static var generation = UUID()
    private static var metadata: [String: UnifiedTrack] = [:]
    static func track(for entryID: String) -> UnifiedTrack? { metadata[entryID] }

    static func cancel() {
        generation = UUID()
        fillTask?.cancel()
        fillTask = nil
    }

    static func reset() { cancel(); metadata = [:] }

    static func start(_ tracks: [UnifiedTrack], positionMS: Int = 0,
                      playing: Bool = true, onError: @escaping @MainActor (String) -> Void) async throws {
        cancel()
        let request = generation
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ProviderError("Allow Apple Music access in Music Services first.")
        }
        guard let first = tracks.first,
              let song = try await AppleMusicProvider.resolveSong(for: first.providerTrackID) else {
            throw ProviderError("Apple Music couldn’t find this song.")
        }
        try Task.checkCancellation()
        guard request == generation else { throw CancellationError() }
        let entry = MusicPlayer.Queue.Entry(song)
        metadata = [entry.id: first]
        let player = ApplicationMusicPlayer.shared
        player.state.shuffleMode = .off
        player.state.repeatMode = MusicPlayer.RepeatMode.none
        player.queue = ApplicationMusicPlayer.Queue([entry])
        try await player.prepareToPlay()
        try Task.checkCancellation()
        guard request == generation else { throw CancellationError() }
        player.playbackTime = Double(positionMS) / 1000
        if playing { try await player.play() }

        // Start the first song immediately; fill the native queue in small
        // batches. Once installed, it continues while Heartable is backgrounded.
        let remaining = Array(tracks.dropFirst())
        fillTask = Task {
            var skipped = 0
            for start in stride(from: 0, to: remaining.count, by: 8) {
                let batch = Array(remaining[start..<min(start + 8, remaining.count)])
                let songs = await withTaskGroup(of: (Int, Song?).self) { group in
                    for (index, track) in batch.enumerated() {
                        group.addTask { (index, try? await AppleMusicProvider.resolveSong(for: track.providerTrackID)) }
                    }
                    var values: [(Int, Song?)] = []
                    for await value in group { values.append(value) }
                    return values.sorted { $0.0 < $1.0 }
                }
                guard !Task.isCancelled, request == generation else { return }
                var entries: [MusicPlayer.Queue.Entry] = []
                for (index, song) in songs {
                    guard let song else { skipped += 1; continue }
                    let entry = MusicPlayer.Queue.Entry(song)
                    metadata[entry.id] = batch[index]
                    entries.append(entry)
                }
                do {
                    if !entries.isEmpty { try await player.queue.insert(entries, position: .tail) }
                }
                catch {
                    guard request == generation, !Task.isCancelled else { return }
                    onError("Apple Music couldn’t finish loading the queue. Tap the playlist’s Play button to retry.")
                    return
                }
            }
            if skipped > 0 { onError("\(skipped) unavailable Apple Music songs were skipped.") }
        }
    }
}
