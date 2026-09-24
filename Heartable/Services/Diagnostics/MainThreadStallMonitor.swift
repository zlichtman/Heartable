import Foundation
import Darwin
import os

/// Detects a main thread that stops answering and records what the app was
/// doing, before iOS can end the process with a watchdog (0x8BADF00D).
///
/// Watchdog reports only carry the frames of the moment iOS gave up, and those
/// are usually deep inside SwiftUI with no Heartable frame at all. This monitor
/// runs on its own thread: once a ping to the main thread goes unanswered for
/// `stallThreshold`, it writes a pending record synchronously to disk with the
/// recent breadcrumbs and a few main-thread stack samples. The record is updated
/// while the stall lasts, finalized if the main thread recovers, and imported
/// into Diagnostics on the next launch if the process never came back.
///
/// Everything stays on this iPhone; it leaves only when the tester shares a
/// report. Breadcrumbs name screens and operations, never songs, playlists,
/// accounts or credentials.
final class MainThreadStallMonitor: @unchecked Sendable {
    static let shared = MainThreadStallMonitor()

    /// Long enough to ignore ordinary slow frames, well inside the 5–10 second
    /// watchdog deadlines.
    static let stallThreshold: Double = 2.0
    /// One wake-up per second keeps the cost negligible, including during
    /// background audio playback.
    private static let tickInterval: Double = 1.0
    private static let maximumBreadcrumbs = 40
    private static let maximumSamples = 12
    private static let maximumFrames = 96

    struct PendingStall: Codable, Equatable, Sendable {
        var build: String
        var startedAt: Date
        var seconds: Double
        var recovered: Bool
        var footprintMB: Int
        var breadcrumbs: [String]
        var samples: [[String]]
    }

    private struct State {
        var breadcrumbs: [(uptime: Double, text: String)] = []
        var started = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let log = Logger(subsystem: "com.zlichtman.heartable", category: "Stall")
    private let queue = DispatchQueue(label: "com.zlichtman.heartable.stall-monitor", qos: .userInitiated)
    private let fileURL: URL?

    // Owned by `queue` only.
    private var timer: DispatchSourceTimer?
    private var lastTick: Double = 0
    private var pingSentAt: Double?
    private var pingID: UInt64 = 0
    private var answeredPingID: UInt64 = 0
    private var stall: PendingStall?
    private var lastSampleAt: Double = 0
    private var lastWriteAt: Double = 0
    private var lastRecordedRecoveryAt: Double?

    // Captured on the main thread in `start()`.
    private var mainThread: thread_act_t = 0
    private var mainStackLow: UInt = 0
    private var mainStackHigh: UInt = 0

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Heartable", isDirectory: true)
        fileURL = base?.appendingPathComponent("pending-stall.json")
    }

    /// Seconds on a clock that pauses while the device sleeps, measured from
    /// the monitor's creation (no boot-time API is involved).
    private static let origin = SuspendingClock.now

    private static func uptime() -> Double {
        let (seconds, attoseconds) = (SuspendingClock.now - origin).components
        return Double(seconds) + Double(attoseconds) / 1_000_000_000_000_000_000
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    /// Adds one short, content-free breadcrumb to the shared monitor.
    static func note(_ text: String) { shared.note(text) }

    /// Adds one short, content-free breadcrumb. Safe from any thread.
    func note(_ text: String) {
        let now = Self.uptime()
        state.withLock { state in
            state.breadcrumbs.append((now, text))
            if state.breadcrumbs.count > Self.maximumBreadcrumbs {
                state.breadcrumbs.removeFirst(state.breadcrumbs.count - Self.maximumBreadcrumbs)
            }
        }
    }

    /// Call once, on the main thread, at launch.
    @MainActor
    func start() {
        let alreadyStarted = state.withLock { state in
            defer { state.started = true }
            return state.started
        }
        guard !alreadyStarted else { return }
        mainThread = mach_thread_self()
        let pthread = pthread_self()
        let high = UInt(bitPattern: pthread_get_stackaddr_np(pthread))
        let size = UInt(pthread_get_stacksize_np(pthread))
        mainStackHigh = high
        mainStackLow = high > size ? high - size : 0
        // Import a record the previous process left before this run can
        // overwrite it with a stall of its own (for example a slow launch).
        if let previous = takePendingStall() {
            let summary = Self.summary(for: previous)
            let payload = Self.payload(for: previous)
            Task { await DiagnosticsStore.shared.record(kind: "stall", build: previous.build,
                                                        summary: summary, payloadJSON: payload) }
        }
        note("launch build \(Self.build)")

        queue.async { [self] in
            lastTick = Self.uptime()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    // MARK: - Monitor thread

    private func tick() {
        let now = Self.uptime()
        let gap = now - lastTick
        lastTick = now
        // A suspended or heavily throttled process skips ticks. That is not a
        // main-thread stall; start over rather than blaming the main thread.
        if gap > Self.tickInterval * 4 {
            pingSentAt = nil
            if stall != nil { finishStall(recovered: true, seconds: nil) }
            return
        }

        guard let sentAt = pingSentAt else {
            sendPing(at: now)
            return
        }
        if answeredPingID == pingID {
            if var finished = stall {
                finished.seconds = max(finished.seconds, now - sentAt)
                stall = finished
                finishStall(recovered: true, seconds: finished.seconds)
            }
            sendPing(at: now)
            return
        }

        let waited = now - sentAt
        guard waited >= Self.stallThreshold else { return }
        if stall == nil {
            stall = PendingStall(
                build: Self.build,
                startedAt: Date().addingTimeInterval(-waited),
                seconds: waited,
                recovered: false,
                footprintMB: MemoryFootprint.megabytes(MemoryFootprint.current()),
                breadcrumbs: breadcrumbLines(relativeTo: now),
                samples: []
            )
            log.error("Main thread unresponsive for \(waited, format: .fixed(precision: 1)) s")
        }
        stall?.seconds = waited
        if stall?.samples.count ?? 0 < Self.maximumSamples, now - lastSampleAt >= Self.tickInterval * 0.9 {
            lastSampleAt = now
            let frames = sampleMainThread()
            if !frames.isEmpty { stall?.samples.append(frames) }
        }
        // The process can be killed at any moment now: keep the file current.
        if now - lastWriteAt >= Self.tickInterval * 0.9 {
            lastWriteAt = now
            if let stall { write(stall) }
        }
    }

    private func sendPing(at now: Double) {
        pingID &+= 1
        let id = pingID
        pingSentAt = now
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            queue.async { self.answeredPingID = id }
        }
    }

    private func finishStall(recovered: Bool, seconds: Double?) {
        guard var finished = stall else { return }
        stall = nil
        lastSampleAt = 0
        lastWriteAt = 0
        if let seconds { finished.seconds = seconds }
        finished.recovered = recovered
        remove()
        // Diagnostics keeps a bounded list; a run of short recovered stalls
        // must not evict crash reports. Long ones are always kept.
        let now = Self.uptime()
        if recovered, finished.seconds < 5,
           let last = lastRecordedRecoveryAt, now - last < 600 { return }
        if recovered { lastRecordedRecoveryAt = now }
        let summary = Self.summary(for: finished)
        let payload = Self.payload(for: finished)
        let build = finished.build
        Task { await DiagnosticsStore.shared.record(kind: "stall", build: build, summary: summary, payloadJSON: payload) }
    }

    private func breadcrumbLines(relativeTo now: Double) -> [String] {
        state.withLock { state in
            state.breadcrumbs.map { String(format: "-%.1fs %@", now - $0.uptime, $0.text) }
        }
    }

    // MARK: - Persistence

    private func write(_ stall: PendingStall) {
        guard let fileURL, let data = try? JSONEncoder().encode(stall) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func remove() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// A pending record left by a process that never recovered, usually the
    /// run iOS ended with a watchdog. Returns and deletes it.
    func takePendingStall() -> PendingStall? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return try? JSONDecoder().decode(PendingStall.self, from: data)
    }

    static func summary(for stall: PendingStall) -> String {
        let outcome = stall.recovered ? "then recovered" : "and the app ended before it recovered"
        let last = stall.breadcrumbs.suffix(3).joined(separator: " → ")
        return String(format: "Main thread unresponsive for %.1f s %@. Last: %@", stall.seconds, outcome, last)
    }

    static func payload(for stall: PendingStall) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(stall)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    // MARK: - Main-thread stack sampling

    /// Walks the suspended main thread's frame-pointer chain. Nothing here may
    /// allocate or take a lock while the main thread is suspended (it may hold
    /// the malloc or dyld lock); addresses are described after it resumes.
    private func sampleMainThread() -> [String] {
        #if arch(arm64)
        guard mainThread != 0 else { return [] }
        let capacity = Self.maximumFrames
        let buffer = UnsafeMutablePointer<UInt>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        var count = 0
        // Strip pointer-authentication bits from return addresses.
        let mask: UInt = 0x0000_007F_FFFF_FFFF
        let low = mainStackLow
        let high = mainStackHigh

        guard thread_suspend(mainThread) == KERN_SUCCESS else { return [] }
        var threadState = arm_thread_state64_t()
        var stateCount = mach_msg_type_number_t(
            MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &threadState) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) {
                thread_get_state(mainThread, thread_state_flavor_t(ARM_THREAD_STATE64), $0, &stateCount)
            }
        }
        if result == KERN_SUCCESS {
            buffer[count] = UInt(threadState.__pc) & mask; count += 1
            buffer[count] = UInt(threadState.__lr) & mask; count += 1
            var framePointer = UInt(threadState.__fp)
            while count < capacity,
                  high >= 16, framePointer >= low, framePointer <= high &- 16,
                  framePointer & 0x7 == 0,
                  let frame = UnsafePointer<UInt>(bitPattern: framePointer) {
                let returnAddress = frame[1] & mask
                guard returnAddress != 0 else { break }
                buffer[count] = returnAddress; count += 1
                let next = frame[0]
                guard next > framePointer else { break }
                framePointer = next
            }
        }
        thread_resume(mainThread)

        var lines: [String] = []
        lines.reserveCapacity(count)
        for index in 0..<count {
            lines.append(Self.describe(buffer[index]))
        }
        return lines
        #else
        return []
        #endif
    }

    /// "Image +offset symbol", matching crash-report conventions so app frames
    /// can be symbolicated against the build's dSYM.
    private static func describe(_ address: UInt) -> String {
        var info = Dl_info()
        guard address > 0, dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0,
              let base = info.dli_fbase else {
            return String(format: "0x%lx", address)
        }
        let image = info.dli_fname.map { URL(fileURLWithPath: String(cString: $0)).lastPathComponent } ?? "?"
        let offset = address &- UInt(bitPattern: base)
        // Release app binaries are stripped: the nearest exported symbol can be
        // unrelated, so its distance is printed exactly like a crash report.
        if let symbol = info.dli_sname, let start = info.dli_saddr {
            let delta = address &- UInt(bitPattern: start)
            return "\(image) +\(offset) \(String(cString: symbol)) + \(delta)"
        }
        return "\(image) +\(offset)"
    }
}
