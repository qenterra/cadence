import CoreGraphics
import Foundation

enum ArtistsPresentation: Hashable, Sendable {
    case overview
    case shelf(ArtistShelfKind)
    case detail(ArtistPreview.ID, origin: ArtistsBrowseOrigin)
}

enum ArtistsBrowseOrigin: Hashable, Sendable {
    case overview
    case shelf(ArtistShelfKind)
    case search
}

enum ArtistShelfKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case recentlyPlayed
    case favorites

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .recentlyPlayed:
            "Recently Played"
        case .favorites:
            "Favorites"
        }
    }
}

enum ArtistsOverviewSection: String, Hashable, Sendable {
    case recentlyPlayed
    case favorites
    case allArtists
}

enum ArtistBrowseAnchor: Hashable, Sendable {
    case section(ArtistsOverviewSection)
    case artist(ArtistPreview.ID)
}

enum ArtistSortField: String, CaseIterable, Hashable, Identifiable, Sendable {
    case name
    case recentlyPlayed
    case albumCount
    case trackCount
    case favoriteDate

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .name:
            "Artist Name"
        case .recentlyPlayed:
            "Recently Played"
        case .albumCount:
            "Album Count"
        case .trackCount:
            "Track Count"
        case .favoriteDate:
            "Recently Favorited"
        }
    }
}

enum ArtistSortDirection: Hashable, Sendable {
    case ascending
    case descending
}

struct ArtistSortDescriptor: Hashable, Sendable {
    let field: ArtistSortField
    let direction: ArtistSortDirection

    static let allArtists = ArtistSortDescriptor(
        field: .name,
        direction: .ascending
    )
    static let recentlyPlayed = ArtistSortDescriptor(
        field: .recentlyPlayed,
        direction: .descending
    )
    static let recentlyFavorited = ArtistSortDescriptor(
        field: .favoriteDate,
        direction: .descending
    )

    static func defaultDescriptor(for field: ArtistSortField) -> Self {
        let direction: ArtistSortDirection = switch field {
        case .name:
            .ascending
        case .recentlyPlayed, .albumCount, .trackCount, .favoriteDate:
            .descending
        }
        return ArtistSortDescriptor(field: field, direction: direction)
    }
}

struct ArtistShelfProjection: Hashable, Sendable {
    let artists: [ArtistPreview]
    let totalCount: Int

    var hasOverflow: Bool {
        artists.count < totalCount
    }
}

struct ArtistsLayoutMetrics: Hashable, Sendable {
    static let horizontalPadding: CGFloat = 28
    static let tileSpacing: CGFloat = 26
    static let minimumTileWidth: CGFloat = 132
    static let maximumTileWidth: CGFloat = 178

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

struct ArtistDetailLayoutMetrics: Hashable, Sendable {
    let artworkSize: CGFloat

    init(totalWidth: CGFloat) {
        artworkSize = min(max(totalWidth * 0.17, 180), 220)
    }
}

struct ArtistTrackTableColumnWidths: Hashable, Sendable {
    let index: CGFloat
    let title: CGFloat
    let album: CGFloat
    let format: CGFloat
    let duration: CGFloat
    let actions: CGFloat

    init(totalWidth: CGFloat) {
        index = 48
        format = 82
        duration = 72
        actions = 42
        let flexible = max(totalWidth - index - format - duration - actions, 360)
        title = max(flexible * 0.52, 188)
        album = max(flexible - title, 172)
    }

    var total: CGFloat {
        index + title + album + format + duration + actions
    }
}

enum ArtistListeningProjection {
    static func sortedArtists(
        _ artists: [ArtistPreview],
        by descriptor: ArtistSortDescriptor,
        recentDates: [ArtistPreview.ID: Date] = [:],
        favoriteDates: [ArtistPreview.ID: Date] = [:]
    ) -> [ArtistPreview] {
        artists.sorted { lhs, rhs in
            let comparison = comparison(
                lhs,
                rhs,
                field: descriptor.field,
                recentDates: recentDates,
                favoriteDates: favoriteDates
            )
            if comparison == .orderedSame {
                return lhs.id < rhs.id
            }
            return descriptor.direction == .ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }

    static func shelf(
        _ artists: [ArtistPreview],
        capacity: Int
    ) -> ArtistShelfProjection {
        ArtistShelfProjection(
            artists: Array(artists.prefix(max(capacity, 0))),
            totalCount: artists.count
        )
    }

    static func mostRecentPlayback(
        in tracks: [TrackPreview]
    ) -> Date? {
        tracks.compactMap(\.lastPlayed).max()
    }

    static func canonicalTracks(
        _ tracks: [TrackPreview]
    ) -> [TrackPreview] {
        tracks.sorted { lhs, rhs in
            if lhs.year != rhs.year {
                return lhs.year < rhs.year
            }
            let albumOrder = compare(lhs.album, rhs.album)
            if albumOrder != .orderedSame {
                return albumOrder == .orderedAscending
            }
            if lhs.discNumber != rhs.discNumber {
                return lhs.discNumber < rhs.discNumber
            }
            if lhs.trackNumber != rhs.trackNumber {
                return lhs.trackNumber < rhs.trackNumber
            }
            return lhs.id < rhs.id
        }
    }

    static func mostPlayed(
        _ tracks: [TrackPreview],
        limit: Int = 5
    ) -> [TrackPreview] {
        Array(
            tracks.sorted { lhs, rhs in
                if lhs.playCount != rhs.playCount {
                    return lhs.playCount > rhs.playCount
                }
                let lhsDate = lhs.lastPlayed ?? .distantPast
                let rhsDate = rhs.lastPlayed ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                let albumOrder = compare(lhs.album, rhs.album)
                if albumOrder != .orderedSame {
                    return albumOrder == .orderedAscending
                }
                if lhs.discNumber != rhs.discNumber {
                    return lhs.discNumber < rhs.discNumber
                }
                if lhs.trackNumber != rhs.trackNumber {
                    return lhs.trackNumber < rhs.trackNumber
                }
                return lhs.id < rhs.id
            }
            .prefix(max(limit, 0))
        )
    }

    static func matchesSearch(
        artist: ArtistPreview,
        query: String,
        derivedTags: [TagPreview]
    ) -> Bool {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedQuery.isEmpty else {
            return true
        }

        return artist.name.localizedStandardContains(normalizedQuery)
            || derivedTags.contains { tag in
                tag.id.localizedStandardContains(normalizedQuery)
                    || tag.displayPath.localizedStandardContains(normalizedQuery)
            }
    }

    private static func comparison(
        _ lhs: ArtistPreview,
        _ rhs: ArtistPreview,
        field: ArtistSortField,
        recentDates: [ArtistPreview.ID: Date],
        favoriteDates: [ArtistPreview.ID: Date]
    ) -> ComparisonResult {
        switch field {
        case .name:
            compare(lhs.name, rhs.name)
        case .recentlyPlayed:
            compare(
                recentDates[lhs.id] ?? .distantPast,
                recentDates[rhs.id] ?? .distantPast
            )
        case .albumCount:
            compare(lhs.albumCount, rhs.albumCount)
        case .trackCount:
            compare(lhs.trackCount, rhs.trackCount)
        case .favoriteDate:
            compare(
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
