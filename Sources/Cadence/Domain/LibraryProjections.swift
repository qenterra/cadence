import Foundation

struct LibraryPageCursor: Codable, Hashable, Sendable {
    let sortValue: String
    let identity: String
}

struct LibraryPage<Element: Sendable>: Sendable {
    let items: [Element]
    let nextCursor: LibraryPageCursor?
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

struct CatalogSearchResults: Equatable, Sendable {
    let tracks: [LibraryTrackProjection]
    let albums: [LibraryAlbumProjection]
    let artists: [LibraryArtistProjection]
    let tags: [LibraryTagProjection]

    static let empty = CatalogSearchResults(
        tracks: [],
        albums: [],
        artists: [],
        tags: []
    )

    var isEmpty: Bool {
        tracks.isEmpty
            && albums.isEmpty
            && artists.isEmpty
            && tags.isEmpty
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
