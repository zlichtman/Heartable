import Foundation

/// The five app sections. Case names are internal identifiers; `title` holds
/// the user-facing label.
enum AppTab: String, CaseIterable, Identifiable {
    // Order = left to right: Heartable, Mixtapes, Library, Backups, Profile.
    case discover, mixtapes, library, backups, profile
    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .discover: "your week, your friends, your sound"
        case .mixtapes: "songs, notes, and photos to give"
        case .library: "every service, one place"
        case .backups: "your library, safely kept"
        case .profile: "you, your sound, your settings"
        }
    }

    var title: String {
        switch self {
        case .discover: "Heartable"
        case .mixtapes: "Mixtapes"
        case .library: "Library"
        case .backups: "Backups"
        case .profile: "Profile"
        }
    }
    var icon: String {
        switch self {
        case .discover: "heart.fill"
        case .mixtapes: "bubble.left.and.bubble.right.fill"
        case .library: "house.fill"
        case .backups: "externaldrive.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}
