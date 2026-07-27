import Foundation

/// Time window for "top tracks" stats. Raw values match the Spotify Web API and
/// the RN model so provider adapters map directly.
enum StatRange: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case shortTerm = "short_term"
    case mediumTerm = "medium_term"
    case longTerm = "long_term"

    var id: String { rawValue }

    /// Short user-facing label.
    var label: String {
        switch self {
        case .shortTerm: "4 weeks"
        case .mediumTerm: "6 months"
        case .longTerm: "All time"
        }
    }

    var compactLabel: String {
        switch self {
        case .shortTerm: "4 wk"
        case .mediumTerm: "6 mo"
        case .longTerm: "All"
        }
    }
}
