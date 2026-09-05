import Foundation

enum NavigationDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
    case home
    case library
    case allTracks
    case albums
    case artists
    case favorites
    case tags
    case smartCollections
    case playlists
    case importMusic
    case trash

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .library: String(localized: "Browse")
        case .allTracks: String(localized: "Tracks")
        case .albums: String(localized: "Albums")
        case .artists: String(localized: "Artists")
        case .favorites: String(localized: "Favorites")
        case .tags: String(localized: "Tags")
        case .smartCollections: String(localized: "Smart Collections")
        case .playlists: String(localized: "Playlists")
        case .importMusic: String(localized: "Import Music")
        case .trash: String(localized: "Trash")
        }
    }

    /// Describes the destination's job when its visible label alone is ambiguous.
    var accessibilityDescription: String {
        switch self {
        case .library:
            String(localized: "Browse artists, albums, and tracks")
        case .allTracks:
            String(localized: "View every track in the library")
        default: title
        }
    }

    var navigationGroup: NavigationRailGroup? {
        switch self {
        case .home, .favorites:
            .listen
        case .library, .allTracks, .albums, .artists:
            .library
        case .playlists, .smartCollections, .tags, .importMusic:
            .organize
        case .trash:
            nil
        }
    }

    var symbolName: String {
        switch self {
        case .home: "house"
        case .library: "music.note.house"
        case .allTracks: "list.bullet.rectangle"
        case .albums: "square.stack"
        case .artists: "person.2"
        case .favorites: "heart.fill"
        case .tags: "tag"
        case .smartCollections: "sparkles.rectangle.stack"
        case .playlists: "music.note.list"
        case .importMusic: "folder.badge.plus"
        case .trash: "trash"
        }
    }
}

enum LibraryRefreshScope: Hashable, Sendable {
    case home
    case library
    case allTracks
    case albums
    case artists
    case favorites
    case playlists
    case tags
    case smartCollections
    case search
    case trash
}

extension NavigationDestination {
    var refreshScope: LibraryRefreshScope? {
        switch self {
        case .home: .home
        case .library: .library
        case .allTracks: .allTracks
        case .albums: .albums
        case .artists: .artists
        case .favorites: .favorites
        case .playlists: .playlists
        case .tags: .tags
        case .smartCollections: .smartCollections
        case .trash: .trash
        case .importMusic: nil
        }
    }
}

enum NavigationRailGroup: String, CaseIterable, Hashable, Identifiable, Sendable {
    case listen
    case library
    case organize

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .listen: String(localized: "Listen")
        case .library: String(localized: "Library")
        case .organize: String(localized: "Organize")
        }
    }
}

enum RepeatMode: String, Codable, Sendable {
    case off
    case all
    case one

    var next: Self {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    var symbolName: String {
        self == .one ? "repeat.1" : "repeat"
    }
}

enum LibrarySearchScope: String, CaseIterable, Identifiable {
    case currentAlbum
    case library

    var id: Self {
        self
    }
}

enum FavoriteCatalogSection: String, CaseIterable, Identifiable {
    case songs
    case albums
    case artists

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .songs: String(localized: "Tracks")
        case .albums: String(localized: "Albums")
        case .artists: String(localized: "Artists")
        }
    }

    var symbolName: String {
        switch self {
        case .songs: "music.note"
        case .albums: "square.stack"
        case .artists: "person.2"
        }
    }
}
