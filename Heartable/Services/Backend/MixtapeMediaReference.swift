import Foundation

enum MixtapeMediaReference {
    static func path(from reference: String) -> String? {
        guard let url = URL(string: reference), url.scheme == "heartable-media",
              url.host == "mixtape-gifts", url.query == nil, url.fragment == nil else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 3, UUID(uuidString: parts[0]) != nil, UUID(uuidString: parts[1]) != nil,
              parts[2].hasSuffix(".jpg"), UUID(uuidString: String(parts[2].dropLast(4))) != nil else { return nil }
        return parts.joined(separator: "/")
    }
}
