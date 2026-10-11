import Foundation

/// The one place library caches are decoded and encoded.
///
/// Every library snapshot (browse cache, playlist index, master library) is
/// megabytes of JSON on a large library, and a decoder or encoder materialises
/// an object graph several times the file size. Serialising all of them on a
/// single actor means those peaks queue instead of stacking, which is what
/// keeps a playlist-heavy account inside the foreground memory limit.
actor LibraryCacheIO {
    static let shared = LibraryCacheIO()

    func load<T: Decodable & Sendable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    func save<T: Encodable & Sendable>(_ value: T, to url: URL?) -> Bool {
        guard let url else { return false }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard !Task.isCancelled, let data = try? JSONEncoder().encode(value) else { return false }
        do { try data.write(to: url, options: .atomic); return true } catch { return false }
    }

    func remove(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
