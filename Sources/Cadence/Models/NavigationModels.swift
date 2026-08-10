enum NavigationDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
    case home
    case library
    case collections
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
        case .collections: "Collections"
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
        case .collections: "rectangle.stack"
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

    var primaryDestination: NavigationDestination {
        switch self {
        case .home:
            .home
        case .library, .allTracks, .albums, .artists, .importMusic, .trash:
            .library
        case .collections, .tags, .smartCollections, .playlists:
            .collections
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

enum LibraryContentSection: String, CaseIterable, Identifiable {
    case tracks
    case albums
    case artists
    case favorites

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .tracks: "Tracks"
        case .albums: "Albums"
        case .artists: "Artists"
        case .favorites: "Favorites"
        }
    }

    var symbolName: String {
        switch self {
        case .tracks: "music.note"
        case .albums: "square.stack"
        case .artists: "person.2"
        case .favorites: "heart"
        }
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
        case .songs: "Songs"
        case .albums: "Albums"
        case .artists: "Artists"
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

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case content
    case columnBrowser

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .content: "Library Sections"
        case .columnBrowser: "Column Browser"
        }
    }

    var symbolName: String {
        switch self {
        case .content: "rectangle.grid.1x2"
        case .columnBrowser: "rectangle.split.3x1"
        }
    }
}

enum CollectionContentSection: String, CaseIterable, Identifiable {
    case playlists
    case smartCollections
    case tags

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .playlists: "Playlists"
        case .smartCollections: "Smart Collections"
        case .tags: "Tags"
        }
    }

    var symbolName: String {
        switch self {
        case .playlists: "music.note.list"
        case .smartCollections: "sparkles.rectangle.stack"
        case .tags: "tag"
        }
    }
}
