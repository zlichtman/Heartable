import Foundation

/// One report MetricKit handed the app about itself: a crash or hang from a
/// previous launch, or a day on which iOS terminated the app abnormally
/// (memory limit, watchdog). Device-level, contains no account data, and
/// leaves the device only when the user shares it from Account.
struct DiagnosticEntry: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let receivedAt: Date
    /// "crash", "hang", "cpu", "diskWrite", or "exits".
    let kind: String
    let build: String
    let summary: String
    let payloadJSON: String

    var shareText: String {
        "Heartable \(kind) report (build \(build), \(receivedAt.formatted(date: .abbreviated, time: .shortened)))\n\(summary)\n\n\(payloadJSON)"
    }
}

/// Keeps the most recent MetricKit reports in Application Support so a tester
/// can hand them over even when Apple's crash pipeline never delivers them.
actor DiagnosticsStore {
    static let shared = DiagnosticsStore()
    static let maxEntries = 30

    private let fileURL: URL?
    private var cached: [DiagnosticEntry]?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Heartable", isDirectory: true)
        fileURL = base?.appendingPathComponent("diagnostics.json")
    }

    func entries() -> [DiagnosticEntry] {
        if let cached { return cached }
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DiagnosticEntry].self, from: data) else {
            cached = []
            return []
        }
        cached = decoded
        return decoded
    }

    @discardableResult
    func record(kind: String, build: String, summary: String, payloadJSON: String) -> DiagnosticEntry {
        let entry = DiagnosticEntry(id: UUID(), receivedAt: Date(), kind: kind, build: build,
                                    summary: summary, payloadJSON: payloadJSON)
        var all = entries()
        all.insert(entry, at: 0)
        if all.count > Self.maxEntries { all = Array(all.prefix(Self.maxEntries)) }
        persist(all)
        return entry
    }

    func clear() {
        persist([])
    }

    private func persist(_ all: [DiagnosticEntry]) {
        cached = all
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
