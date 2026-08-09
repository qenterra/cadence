import Foundation

struct LibraryPageCursor: Codable, Hashable, Sendable {
    let sortValue: String
    let identity: String
    let offset: Int?

    init(
        sortValue: String,
        identity: String,
        offset: Int? = nil
    ) {
        self.sortValue = sortValue
        self.identity = identity
        self.offset = offset
    }

    static func offset(_ value: Int) -> LibraryPageCursor {
        LibraryPageCursor(
            sortValue: "",
            identity: "",
            offset: value
        )
    }
}

struct LibraryPage<Element: Sendable>: Sendable {
    let items: [Element]
    let nextCursor: LibraryPageCursor?
}

enum LibraryTrackScope: Hashable, Sendable {
    case all
    case artist(UUID)
    case album(UUID)
}

enum LibraryTrackSortField: String, Codable, CaseIterable, Sendable {
    case song
    case album
    case year
    case dateAdded
    case playCount
    case duration
}

enum LibraryTrackSortDirection: String, Codable, Sendable {
    case ascending
    case descending
}

struct LibraryTrackSort: Codable, Hashable, Sendable {
    let field: LibraryTrackSortField
    let direction: LibraryTrackSortDirection

    static let titleAscending = LibraryTrackSort(
        field: .song,
        direction: .ascending
    )
}

struct LibraryTrackQuery: Hashable, Sendable {
    let scope: LibraryTrackScope
    let search: String
    let sort: LibraryTrackSort

    init(
        scope: LibraryTrackScope = .all,
        search: String = "",
        sort: LibraryTrackSort = .titleAscending
    ) {
        self.scope = scope
        self.search = SearchNormalizer.normalize(search)
        self.sort = sort
    }

    static let allTracks = LibraryTrackQuery()
}

struct LibraryTrackProjection: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let artistID: UUID?
    let artist: String
    let albumID: UUID?
    let album: String
    let duration: TimeInterval
    let year: Int?
    let codec: String
    let sampleRate: Double
    let channelCount: Int
    let bitDepth: Int?
    let isFavorite: Bool
    let customArtworkID: UUID?
    let artworkID: UUID?
    let relativeMediaPath: String
    let dateAdded: Date
    let lastPlayedAt: Date?
    let playCount: Int
    let hasSynchronizedLyrics: Bool
}

enum PlaybackQueueTrackState: Hashable, Sendable {
    case loading
    case available(LibraryTrackProjection)
    case unavailable
    case failed(String)
}

struct PlaybackQueueTrackProjection: Identifiable, Hashable, Sendable {
    let id: UUID
    let state: PlaybackQueueTrackState

    var track: LibraryTrackProjection? {
        guard case let .available(track) = state else {
            return nil
        }
        return track
    }
}

struct LibraryArtistProjection: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let albumCount: Int
    let trackCount: Int
    let isFavorite: Bool
    let favoriteDate: Date?
    let customArtworkID: UUID?
}

struct LibraryAlbumProjection: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let artistID: UUID?
    let artist: String
    let year: Int?
    let dateAdded: Date
    let trackCount: Int
    let totalDuration: TimeInterval
    let isFavorite: Bool
    let favoriteDate: Date?
    let customArtworkID: UUID?
}

struct LibraryTagProjection: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayPath: String
    let groupPath: String?
}

struct LibraryPlaylistProjection: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let trackCount: Int
    let totalDuration: TimeInterval
    let modifiedAt: Date
    let customArtworkID: UUID?
}

struct ManagedArtworkProjection: Identifiable, Hashable, Sendable {
    let id: UUID
    let relativePath: String
    let revision: Int
    let scale: Double
    let normalizedOffsetX: Double
    let normalizedOffsetY: Double
}

struct LibraryTrashProjection: Identifiable, Hashable, Sendable {
    let id: UUID
    let targetKind: TrashTargetKind
    let targetIDs: [UUID]
    let relativePaths: [String]
    let createdAt: Date

    var itemCount: Int {
        targetIDs.count
    }
}

struct LibraryCatalogCounts: Equatable, Sendable {
    let liveTrackCount: Int
    let trashedTrackCount: Int

    static let empty = LibraryCatalogCounts(
        liveTrackCount: 0,
        trashedTrackCount: 0
    )
}

enum CatalogSearchGroup: String, CaseIterable, Hashable, Identifiable, Sendable {
    case artists
    case albums
    case tags
    case tracks

    var id: Self {
        self
    }
}

struct CatalogSearchResults: Equatable, Sendable {
    var tracks: [LibraryTrackProjection]
    var albums: [LibraryAlbumProjection]
    var artists: [LibraryArtistProjection]
    var tags: [LibraryTagProjection]
    var trackCursor: LibraryPageCursor?
    var albumCursor: LibraryPageCursor?
    var artistCursor: LibraryPageCursor?
    var tagCursor: LibraryPageCursor?

    static let empty = CatalogSearchResults(
        tracks: [],
        albums: [],
        artists: [],
        tags: [],
        trackCursor: nil,
        albumCursor: nil,
        artistCursor: nil,
        tagCursor: nil
    )

    var isEmpty: Bool {
        tracks.isEmpty
            && albums.isEmpty
            && artists.isEmpty
            && tags.isEmpty
    }

    func hasMore(_ group: CatalogSearchGroup) -> Bool {
        switch group {
        case .artists: artistCursor != nil
        case .albums: albumCursor != nil
        case .tags: tagCursor != nil
        case .tracks: trackCursor != nil
        }
    }
}

struct PlaybackTrack: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let artistID: UUID?
    let artist: String
    let albumID: UUID?
    let album: String
    let year: Int?
    let discNumber: Int?
    let trackNumber: Int?
    let duration: TimeInterval
    let codec: String
    let container: String
    let sampleRate: Double
    let channelCount: Int
    let bitrate: Int?
    let bitDepth: Int?
    let spatialFormat: StoredSpatialFormat
    let relativeMediaPath: String
    let lyricRelativePath: String?
    let artworkID: UUID?
    let replayGainTrackGain: Double?
    let replayGainTrackPeak: Double?

    init(
        id: UUID,
        title: String,
        artistID: UUID?,
        artist: String,
        albumID: UUID?,
        album: String,
        duration: TimeInterval,
        codec: String,
        container: String,
        sampleRate: Double,
        channelCount: Int,
        bitrate: Int?,
        bitDepth: Int?,
        spatialFormat: StoredSpatialFormat,
        relativeMediaPath: String,
        lyricRelativePath: String?,
        artworkID: UUID?,
        replayGainTrackGain: Double?,
        replayGainTrackPeak: Double?,
        year: Int? = nil,
        discNumber: Int? = nil,
        trackNumber: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artistID = artistID
        self.artist = artist
        self.albumID = albumID
        self.album = album
        self.year = year
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.duration = duration
        self.codec = codec
        self.container = container
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitrate = bitrate
        self.bitDepth = bitDepth
        self.spatialFormat = spatialFormat
        self.relativeMediaPath = relativeMediaPath
        self.lyricRelativePath = lyricRelativePath
        self.artworkID = artworkID
        self.replayGainTrackGain = replayGainTrackGain
        self.replayGainTrackPeak = replayGainTrackPeak
    }
}
