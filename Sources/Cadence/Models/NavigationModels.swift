enum NavigationDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
    case home
    case library
    case allTracks
    case albums
    case artists
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
        case .home: "Home"
        case .library: "Library"
        case .allTracks: "All Tracks"
        case .albums: "Albums"
        case .artists: "Artists"
        case .tags: "Tags"
        case .smartCollections: "Smart Collections"
        case .playlists: "Playlists"
        case .importMusic: "Import Music"
        case .trash: "Trash"
        }
    }

    var symbolName: String {
        switch self {
        case .home: "house"
        case .library: "music.note.house"
        case .allTracks: "list.bullet.rectangle"
        case .albums: "square.stack"
        case .artists: "person.2"
        case .tags: "tag"
        case .smartCollections: "sparkles.rectangle.stack"
        case .playlists: "music.note.list"
        case .importMusic: "folder.badge.plus"
        case .trash: "trash"
        }
    }
}

enum RepeatMode: String, Sendable {
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

    var title: String {
        switch self {
        case .currentAlbum: "Album"
        case .library: "Library"
        }
    }
}
