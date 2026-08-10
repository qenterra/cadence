import Foundation
import SwiftData

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
    // Kept only to reopen V4 libraries. Cadence no longer reads or updates it.
    var dateAdded: Date
    var lastPlayedAt: Date?
    // Kept only to reopen V4 libraries. Cadence no longer reads or updates it.
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

    var spatialFormat: StoredSpatialFormat {
        get {
            StoredSpatialFormat(rawValue: spatialFormatRawValue) ?? .unknown
        }
        set {
            spatialFormatRawValue = newValue.rawValue
        }
    }

    func rename(to title: String) {
        self.title = title
        normalizedTitle = SearchNormalizer.normalize(title)
    }
}

enum StoredSpatialFormat: String, Codable, CaseIterable, Sendable {
    case unknown
    case stereo
    case multichannel
    case dolbyAtmos
}
