import Foundation

struct WSUMBroadcast: Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL
}

struct WSUMSpin: Identifiable, Sendable {
    let id: String
    let artist: String
    let song: String
    let album: String
    let time: String
}

/// Reads public station-owned pages as data. No web view, tracking scripts or
/// external navigation. Markup changes fail visibly, never become empty history.
actor WSUMArchive {
    static let shared = WSUMArchive()
    private struct Page: Codable { let html: String; let fetchedAt: Date }
    private var pages: [String: Page] = [:]
    private var requests: [String: Task<String, Error>] = [:]

    func page(_ url: URL) async throws -> String {
        guard Self.allowed(url) else { throw URLError(.unsupportedURL) }
        let key = url.pathComponents.prefix(4).joined(separator: "-")
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("heartable-radio-\(key).json")
        if pages[key] == nil, let file, let data = try? Data(contentsOf: file) {
            pages[key] = try? JSONDecoder().decode(Page.self, from: data)
        }
        if let cached = pages[key], Date().timeIntervalSince(cached.fetchedAt) < 900 { return cached.html }
        if let request = requests[key] { return try await request.value }
        let request = Task<String, Error> {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let finalURL = response.url, Self.allowed(finalURL), data.count < 3_000_000,
                  let html = String(data: data, encoding: .utf8), html.contains("show-title") else {
                throw URLError(.cannotParseResponse)
            }
            return html
        }
        requests[key] = request
        defer { requests[key] = nil }
        do {
            let html = try await request.value
            let page = Page(html: html, fetchedAt: .now)
            pages[key] = page
            if let file, let data = try? JSONEncoder().encode(page) { try? data.write(to: file, options: .atomic) }
            return html
        } catch {
            if let cached = pages[key] { return cached.html }
            throw error
        }
    }

    nonisolated static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "spinitron.com" &&
            (url.path.hasPrefix("/WSUM/show/") || url.path.hasPrefix("/WSUM/pl/"))
    }

    nonisolated static func broadcasts(_ html: String) throws -> [WSUMBroadcast] {
        guard html.contains("playlist-list") else { throw URLError(.cannotParseResponse) }
        var seen = Set<String>()
        return matches(#"<div class="list-item" data-key="([0-9]+)">([\s\S]*?)(?=<div class="list-item"|<ul class="pagination"|$)"#, html).compactMap { fields in
            guard fields.count == 3, seen.insert(fields[1]).inserted,
                  let raw = matches(#"href="(https://spinitron.com/WSUM/pl/[^\"]+)""#, fields[2]).first?[1],
                  let url = URL(string: text(raw)), allowed(url),
                  let label = matches(#"<p class="timeslot">([\s\S]*?)</p>"#, fields[2]).first?[1] else { return nil }
            return WSUMBroadcast(id: fields[1], title: text(label), url: url)
        }
    }

    nonisolated static func spins(_ html: String) throws -> [WSUMSpin] {
        guard html.contains("public-spins") else { throw URLError(.cannotParseResponse) }
        return matches(#"<tr id="sp-([0-9]+)"([\s\S]*?)</tr>"#, html).compactMap { row in
            guard let raw = matches(#"data-spin="([^\"]*)""#, row[2]).first?[1],
                  let data = text(raw).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let song = object["s"] as? String, !song.isEmpty else { return nil }
            let time = matches(#"class="spin-time">[\s\S]*?<a[^>]*>(.*?)</a>"#, row[2]).first?[1] ?? ""
            return WSUMSpin(id: row[1], artist: object["a"] as? String ?? "", song: song,
                            album: object["r"] as? String ?? "", time: text(time))
        }
    }

    nonisolated static func matches(_ pattern: String, _ value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let string = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: string.length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : string.substring(with: match.range(at: $0)) }
        }
    }

    nonisolated static func text(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for match in matches(#"&#(x[0-9A-Fa-f]+|[0-9]+);"#, result).reversed() {
            let number = match[1]
            if let code = UInt32(number.hasPrefix("x") ? String(number.dropFirst()) : number,
                                 radix: number.hasPrefix("x") ? 16 : 10), let scalar = UnicodeScalar(code) {
                result = result.replacingOccurrences(of: match[0], with: String(scalar))
            }
        }
        for (entity, character) in [("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
