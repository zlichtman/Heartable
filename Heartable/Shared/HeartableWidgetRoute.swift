import Foundation

/// A small, allow-listed navigation contract; no credentials or account IDs in URLs.
enum HeartableWidgetRoute: String, CaseIterable, Hashable {
    case library, friends, backups, recap

    var url: URL { URL(string: "heartable://widget/\(rawValue)")! }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "heartable",
              url.host?.lowercased() == "widget",
              url.query == nil, url.fragment == nil,
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        self.init(rawValue: String(url.path.dropFirst()))
    }
}
