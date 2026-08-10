import Foundation
import SwiftData

enum CadenceLegacySchemaModels {
    @Model
    final class ArtistRecord {
        #Index<ArtistRecord>(
            [\.normalizedName],
            [\.normalizedName, \.sortIdentity],
            [\.favoriteDate]
        )

        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var sortIdentity: String
        var name: String
        var normalizedName: String
        var isFavorite: Bool
        var favoriteDate: Date?
        var trackCount: Int
        var albumCount: Int
        var customArtworkID: UUID?

        @Relationship(deleteRule: .nullify, inverse: \TrackRecord.artist)
        var tracks: [TrackRecord]

        @Relationship(deleteRule: .nullify, inverse: \AlbumRecord.artist)
        var albums: [AlbumRecord]

        init(
            id: UUID = UUID(),
            name: String,
            isFavorite: Bool = false,
            favoriteDate: Date? = nil,
            trackCount: Int = 0,
            albumCount: Int = 0,
            customArtworkID: UUID? = nil
        ) {
            self.id = id
            sortIdentity = id.uuidString
            self.name = name
            normalizedName = SearchNormalizer.normalize(name)
            self.isFavorite = isFavorite
            self.favoriteDate = favoriteDate
            self.trackCount = trackCount
            self.albumCount = albumCount
            self.customArtworkID = customArtworkID
            tracks = []
            albums = []
        }
    }

    @Model
    final class AlbumRecord {
        #Index<AlbumRecord>(
            [\.normalizedTitle],
            [\.normalizedTitle, \.sortIdentity],
            [\.year],
            [\.dateAdded]
        )

        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var sortIdentity: String
        var title: String
        var normalizedTitle: String
        var year: Int?
        var dateAdded: Date
        var isFavorite: Bool
        var favoriteDate: Date?
        var trackCount: Int
        var totalDuration: TimeInterval
        var customArtworkID: UUID?
        var artist: ArtistRecord?

        @Relationship(deleteRule: .nullify, inverse: \TrackRecord.album)
        var tracks: [TrackRecord]

        init(
            id: UUID = UUID(),
            title: String,
            artist: ArtistRecord? = nil,
            year: Int? = nil,
            dateAdded: Date = .now,
            isFavorite: Bool = false,
            favoriteDate: Date? = nil,
            trackCount: Int = 0,
            totalDuration: TimeInterval = 0,
            customArtworkID: UUID? = nil
        ) {
            self.id = id
            sortIdentity = id.uuidString
            self.title = title
            normalizedTitle = SearchNormalizer.normalize(title)
            self.artist = artist
            self.year = year
            self.dateAdded = dateAdded
            self.isFavorite = isFavorite
            self.favoriteDate = favoriteDate
            self.trackCount = trackCount
            self.totalDuration = totalDuration
            self.customArtworkID = customArtworkID
            tracks = []
        }
    }
}

extension CadenceLegacySchemaModels {
    @Model
    final class TrackRecord {
        #Index<TrackRecord>(
            [\.normalizedTitle],
            [\.normalizedTitle, \.sortIdentity],
            [\.dateAdded],
            [\.lastPlayedAt],
            [\.importSessionID]
        )

        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var sortIdentity: String
        @Attribute(.unique) var contentHash: String
        var originalFilename: String
        var originalExtension: String
        var title: String
        var normalizedTitle: String
        var trackNumber: Int?
        var discNumber: Int?
        var duration: TimeInterval
        var sourceFrameCount: Int64?
        var dateAdded: Date
        var lastPlayedAt: Date?
        var playCount: Int
        var skipCount: Int
        var isFavorite: Bool
        var codec: String
        var container: String
        var sampleRate: Double
        var channelCount: Int
        var bitrate: Int?
        var bitDepth: Int?
        var spatialFormatRawValue: String
        var relativeMediaPath: String
        var sourceMetadata: Data?
        var importSessionID: UUID
        var customArtworkID: UUID?
        var replayGainTrackGain: Double?
        var replayGainTrackPeak: Double?
        var artist: ArtistRecord?
        var album: AlbumRecord?

        @Relationship(deleteRule: .cascade, inverse: \LyricRecord.track)
        var lyrics: LyricRecord?

        init(
            id: UUID = UUID(),
            originalFilename: String,
            title: String,
            duration: TimeInterval,
            codec: String,
            container: String,
            sampleRate: Double,
            channelCount: Int,
            bitDepth: Int? = nil,
            bitrate: Int? = nil,
            contentHash: String,
            relativeMediaPath: String,
            importSessionID: UUID,
            artist: ArtistRecord? = nil,
            album: AlbumRecord? = nil,
            trackNumber: Int? = nil,
            discNumber: Int? = nil,
            sourceFrameCount: Int64? = nil,
            dateAdded: Date = .now,
            lastPlayedAt: Date? = nil,
            playCount: Int = 0,
            skipCount: Int = 0,
            isFavorite: Bool = false,
            spatialFormat: StoredSpatialFormat = .unknown,
            sourceMetadata: Data? = nil,
            customArtworkID: UUID? = nil,
            replayGainTrackGain: Double? = nil,
            replayGainTrackPeak: Double? = nil
        ) {
            self.id = id
            sortIdentity = id.uuidString
            self.originalFilename = originalFilename
            originalExtension = URL(filePath: originalFilename).pathExtension
                .lowercased()
            self.title = title
            normalizedTitle = SearchNormalizer.normalize(title)
            self.trackNumber = trackNumber
            self.discNumber = discNumber
            self.duration = duration
            self.sourceFrameCount = sourceFrameCount
            self.dateAdded = dateAdded
            self.lastPlayedAt = lastPlayedAt
            self.playCount = playCount
            self.skipCount = skipCount
            self.isFavorite = isFavorite
            self.codec = codec
            self.container = container
            self.sampleRate = sampleRate
            self.channelCount = channelCount
            self.bitrate = bitrate
            self.bitDepth = bitDepth
            spatialFormatRawValue = spatialFormat.rawValue
            self.contentHash = contentHash
            self.relativeMediaPath = relativeMediaPath
            self.sourceMetadata = sourceMetadata
            self.importSessionID = importSessionID
            self.customArtworkID = customArtworkID
            self.replayGainTrackGain = replayGainTrackGain
            self.replayGainTrackPeak = replayGainTrackPeak
            self.artist = artist
            self.album = album
        }
    }

    @Model
    final class LyricRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var trackID: UUID
        var relativePath: String
        var textEncoding: String
        var parsingStatusRawValue: String
        var timingStatusRawValue: String
        var contentHash: String
        var modifiedAt: Date
        var track: TrackRecord?

        init(
            id: UUID = UUID(),
            relativePath: String,
            textEncoding: String = "UTF-8",
            parsingStatus: StoredLyricParsingStatus = .valid,
            contentHash: String,
            timingStatus: LyricTimingStatus,
            modifiedAt: Date = .now,
            track: TrackRecord
        ) {
            self.id = id
            trackID = track.id
            self.relativePath = relativePath
            self.textEncoding = textEncoding
            parsingStatusRawValue = parsingStatus.rawValue
            timingStatusRawValue = timingStatus.storageRawValue
            self.contentHash = contentHash
            self.modifiedAt = modifiedAt
            self.track = track
        }
    }

    @Model
    final class PlaylistEntryRecord {
        #Index<PlaylistEntryRecord>(
            [\.playlistID, \.position],
            [\.playlistID, \.trackID],
            [\.trackID]
        )

        @Attribute(.unique) var id: UUID
        var playlistID: UUID
        var trackID: UUID
        var position: Int
        var dateAdded: Date

        init(
            id: UUID = UUID(),
            playlistID: UUID,
            trackID: UUID,
            position: Int,
            dateAdded: Date = .now
        ) {
            self.id = id
            self.playlistID = playlistID
            self.trackID = trackID
            self.position = position
            self.dateAdded = dateAdded
        }
    }
}
