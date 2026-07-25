import CoreGraphics
import Foundation

enum AlbumsPresentation: Hashable, Sendable {
    case overview
    case shelf(AlbumShelfKind)
    case detail(AlbumPreview.ID, origin: AlbumsBrowseOrigin)
}

enum AlbumsBrowseOrigin: Hashable, Sendable {
    case overview
    case shelf(AlbumShelfKind)
    case search
}

enum AlbumShelfKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case recentlyAdded
    case favorites

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .recentlyAdded:
            "Recently Added"
        case .favorites:
            "Favorites"
        }
    }
}

enum AlbumsOverviewSection: String, Hashable, Sendable {
    case recentlyAdded
    case favorites
    case allAlbums
}

enum AlbumBrowseAnchor: Hashable, Sendable {
    case section(AlbumsOverviewSection)
    case album(AlbumPreview.ID)
}

enum AlbumSortField: String, CaseIterable, Hashable, Identifiable, Sendable {
    case artist
    case title
    case dateAdded
    case releaseYear
    case favoriteDate

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .artist:
            "Artist"
        case .title:
            "Album Title"
        case .dateAdded:
            "Recently Added"
        case .releaseYear:
            "Release Year"
        case .favoriteDate:
            "Recently Favorited"
        }
    }
}

enum AlbumSortDirection: Hashable, Sendable {
    case ascending
    case descending
}

struct AlbumSortDescriptor: Hashable, Sendable {
    let field: AlbumSortField
    let direction: AlbumSortDirection

    static let allAlbums = AlbumSortDescriptor(
        field: .artist,
        direction: .ascending
    )
    static let recentlyAdded = AlbumSortDescriptor(
        field: .dateAdded,
        direction: .descending
    )
    static let recentlyFavorited = AlbumSortDescriptor(
        field: .favoriteDate,
        direction: .descending
    )

    static func defaultDescriptor(for field: AlbumSortField) -> Self {
        let direction: AlbumSortDirection = switch field {
        case .artist, .title:
            .ascending
        case .dateAdded, .releaseYear, .favoriteDate:
            .descending
        }
        return AlbumSortDescriptor(field: field, direction: direction)
    }
}

struct AlbumShelfProjection: Hashable, Sendable {
    let albums: [AlbumPreview]
    let totalCount: Int

    var hasOverflow: Bool {
        albums.count < totalCount
    }
}

enum AlbumTrackTagSource: Hashable, Sendable {
    case direct
    case inherited
    case excluded

    var title: String {
        switch self {
        case .direct:
            "Direct track tag"
        case .inherited:
            "Inherited from album"
        case .excluded:
            "Excluded from track"
        }
    }
}

struct AlbumTrackTagItem: Identifiable, Hashable, Sendable {
    let tag: TagPreview
    let source: AlbumTrackTagSource

    var id: TagPreview.ID {
        tag.id
    }
}

struct AlbumsLayoutMetrics: Hashable, Sendable {
    static let horizontalPadding: CGFloat = 28
    static let tileSpacing: CGFloat = 24
    static let minimumTileWidth: CGFloat = 148
    static let maximumTileWidth: CGFloat = 196

    let columnCount: Int
    let tileWidth: CGFloat

    init(totalWidth: CGFloat) {
        let contentWidth = max(
            totalWidth - Self.horizontalPadding * 2,
            Self.minimumTileWidth
        )
        let fittedColumns = Int(
            (contentWidth + Self.tileSpacing)
                / (Self.minimumTileWidth + Self.tileSpacing)
        )
        columnCount = max(fittedColumns, 1)
        let proposedWidth = (
            contentWidth - CGFloat(columnCount - 1) * Self.tileSpacing
        ) / CGFloat(columnCount)
        tileWidth = min(
            max(proposedWidth, Self.minimumTileWidth),
            Self.maximumTileWidth
        )
    }

    var shelfCapacity: Int {
        columnCount
    }
}

struct AlbumDetailLayoutMetrics: Hashable, Sendable {
    let artworkSize: CGFloat

    init(totalWidth: CGFloat) {
        artworkSize = min(max(totalWidth * 0.17, 180), 220)
    }
}

struct AlbumTrackTableColumnWidths: Hashable, Sendable {
    let index: CGFloat
    let title: CGFloat
    let format: CGFloat
    let duration: CGFloat
    let actions: CGFloat

    init(totalWidth: CGFloat) {
        index = 48
        format = 92
        duration = 72
        actions = 44
        title = max(totalWidth - index - format - duration - actions, 180)
    }

    var total: CGFloat {
        index + title + format + duration + actions
    }
}

enum AlbumListeningProjection {
    static func sortedAlbums(
        _ albums: [AlbumPreview],
        by descriptor: AlbumSortDescriptor,
        favoriteDates: [AlbumPreview.ID: Date] = [:]
    ) -> [AlbumPreview] {
        albums.sorted { lhs, rhs in
            let order = comparison(
                lhs,
                rhs,
                field: descriptor.field,
                favoriteDates: favoriteDates
            )
            if order == .orderedSame {
                return lhs.id < rhs.id
            }
            return descriptor.direction == .ascending
                ? order == .orderedAscending
                : order == .orderedDescending
        }
    }

    static func shelf(
        _ albums: [AlbumPreview],
        capacity: Int
    ) -> AlbumShelfProjection {
        AlbumShelfProjection(
            albums: Array(albums.prefix(max(capacity, 0))),
            totalCount: albums.count
        )
    }

    static func canonicalTracks(
        _ tracks: [TrackPreview]
    ) -> [TrackPreview] {
        tracks.sorted { lhs, rhs in
            if lhs.discNumber != rhs.discNumber {
                return lhs.discNumber < rhs.discNumber
            }
            if lhs.trackNumber != rhs.trackNumber {
                return lhs.trackNumber < rhs.trackNumber
            }
            return lhs.id < rhs.id
        }
    }

    static func matchesSearch(
        album: AlbumPreview,
        query: String,
        assignedTags: [TagPreview]
    ) -> Bool {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedQuery.isEmpty else {
            return true
        }

        return album.title.localizedStandardContains(normalizedQuery)
            || album.artist.localizedStandardContains(normalizedQuery)
            || assignedTags.contains { tag in
                tag.id.localizedStandardContains(normalizedQuery)
                    || tag.displayPath.localizedStandardContains(normalizedQuery)
            }
    }

    private static func comparison(
        _ lhs: AlbumPreview,
        _ rhs: AlbumPreview,
        field: AlbumSortField,
        favoriteDates: [AlbumPreview.ID: Date]
    ) -> ComparisonResult {
        switch field {
        case .artist:
            let artistOrder = compare(lhs.artist, rhs.artist)
            return artistOrder == .orderedSame
                ? compare(lhs.title, rhs.title)
                : artistOrder
        case .title:
            return compare(lhs.title, rhs.title)
        case .dateAdded:
            return compare(lhs.dateAdded, rhs.dateAdded)
        case .releaseYear:
            return compare(lhs.year, rhs.year)
        case .favoriteDate:
            return compare(
                favoriteDates[lhs.id] ?? .distantPast,
                favoriteDates[rhs.id] ?? .distantPast
            )
        }
    }

    private static func compare(
        _ lhs: String,
        _ rhs: String
    ) -> ComparisonResult {
        let locale = Locale(identifier: "en_US_POSIX")
        let options: String.CompareOptions = [
            .caseInsensitive,
            .diacriticInsensitive,
            .widthInsensitive,
        ]
        let normalizedLHS = lhs.folding(options: options, locale: locale)
        let normalizedRHS = rhs.folding(options: options, locale: locale)
        return normalizedLHS.compare(
            normalizedRHS,
            options: .literal,
            locale: locale
        )
    }

    private static func compare<T: Comparable>(
        _ lhs: T,
        _ rhs: T
    ) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }
}
