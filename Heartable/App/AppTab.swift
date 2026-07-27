import Foundation

/// The five app sections. Names are ours (Spotify-style layout, not labels).
enum AppTab: String, CaseIterable, Identifiable {
    // Order = left to right: Heartable, Chats, Library, Backups, Profile.
    case discover, chats, library, backups, profile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: "Heartable"
        case .chats: "Chats"
        case .library: "Library"
        case .backups: "Backups"
        case .profile: "Profile"
        }
    }
    var icon: String {
        switch self {
        case .discover: "heart.fill"
        case .chats: "bubble.left.and.bubble.right.fill"
        case .library: "house.fill"
        case .backups: "externaldrive.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}
