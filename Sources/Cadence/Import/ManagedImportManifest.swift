import Foundation

enum ManagedImportEntryState: String, Codable, Sendable {
    case pending
    case copied
    case failed
}

enum ManagedImportManifestError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case invalidTransition(
        from: ManagedImportManifest.State,
        to: ManagedImportManifest.State
    )
    case duplicateTrackID(UUID)
    case duplicateTargetPath(String)
    case invalidTargetPath(String)
    case invalidContentHash(String)
    case invalidEntryState(UUID)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "Import manifest version \(version) is not supported."
        case let .invalidTransition(from, to):
            "Import manifest cannot move from \(from.rawValue) to \(to.rawValue)."
        case let .duplicateTrackID(id):
            "Import manifest repeats track \(id.uuidString)."
        case let .duplicateTargetPath(path):
            "Import manifest repeats managed target \(path)."
        case let .invalidTargetPath(path):
            "Import manifest contains an invalid managed target: \(path)."
        case let .invalidContentHash(hash):
            "Import manifest contains an invalid SHA-256 hash: \(hash)."
        case let .invalidEntryState(id):
            "Import manifest has an inconsistent state for \(id.uuidString)."
        }
    }
}

struct ManagedImportManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1

    enum State: String, Codable, CaseIterable, Sendable {
        case prepared
        case copied
        case filesCommitted
        case storeCommitted
        case complete
        case rollbackRequired
    }

    struct Metadata: Codable, Equatable, Sendable {
        let title: String
        let artist: String
        let album: String
        let artists: [String]?
        let albumArtist: String?
        let year: Int?
        let trackNumber: Int?
        let discNumber: Int?
        let duration: TimeInterval
        let codec: String
        let container: String
        let sampleRate: Double
        let channelCount: Int
        let bitrate: Int?
        let bitDepth: Int?
        let spatialFormat: StoredSpatialFormat
        let embeddedLyrics: EmbeddedLyricsPayload?
        let sourceMetadata: SourceMetadataSnapshot?

        init(_ metadata: ScannedAudioMetadata) {
            title = metadata.title
            artist = metadata.artist
            album = metadata.album
            artists = metadata.artists
            albumArtist = metadata.albumArtist
            year = metadata.year
            trackNumber = metadata.trackNumber
            discNumber = metadata.discNumber
            duration = metadata.duration
            codec = metadata.codec
            container = metadata.container
            sampleRate = metadata.sampleRate
            channelCount = metadata.channelCount
            bitrate = metadata.bitrate
            bitDepth = metadata.bitDepth
            spatialFormat = metadata.spatialFormat
            embeddedLyrics = metadata.embeddedLyrics
            sourceMetadata = metadata.sourceMetadata
        }

        init(
            title: String,
            artist: String,
            album: String,
            artists: [String]? = nil,
            albumArtist: String? = nil,
            year: Int?,
            trackNumber: Int?,
            discNumber: Int?,
            duration: TimeInterval,
            codec: String,
            container: String,
            sampleRate: Double,
            channelCount: Int,
            bitrate: Int?,
            bitDepth: Int?,
            spatialFormat: StoredSpatialFormat,
            embeddedLyrics: EmbeddedLyricsPayload? = nil,
            sourceMetadata: SourceMetadataSnapshot? = nil
        ) {
            self.title = title
            self.artist = artist
            self.album = album
            self.artists = artists
            self.albumArtist = albumArtist
            self.year = year
            self.trackNumber = trackNumber
            self.discNumber = discNumber
            self.duration = duration
            self.codec = codec
            self.container = container
            self.sampleRate = sampleRate
            self.channelCount = channelCount
            self.bitrate = bitrate
            self.bitDepth = bitDepth
            self.spatialFormat = spatialFormat
            self.embeddedLyrics = embeddedLyrics
            self.sourceMetadata = sourceMetadata
        }

        var creditArtistNames: [String] {
            ArtistCreditParser().parse(
                values: artists ?? [artist],
                fallback: artist
            )
        }

        var albumArtistName: String {
            ArtistCreditParser().parse(
                values: albumArtist.map { [$0] } ?? [],
                fallback: creditArtistNames[0]
            )[0]
        }
    }

    struct LyricAsset: Codable, Equatable, Sendable {
        var relativePath: String
        var contentHash: String?
        var timingStatus: String?
    }

    struct ArtworkAsset: Codable, Equatable, Sendable {
        let id: UUID
        let relativePath: String
        let contentHash: String
        let format: String
        let pixelWidth: Int
        let pixelHeight: Int
    }

    struct Entry: Codable, Equatable, Sendable {
        let trackID: UUID
        let sourceAudioPath: String
        let sourceLyricPath: String?
        let originalFilename: String
        let originalExtension: String
        let metadata: Metadata
        let expectedAudioHash: String
        let sizeInBytes: Int64
        var relativeMediaPath: String
        var lyric: LyricAsset?
        var artwork: ArtworkAsset?
        var state: ManagedImportEntryState
        var failureReason: String?
    }

    let version: Int
    let importID: UUID
    let sourceDisplayName: String
    let createdAt: Date
    let state: State
    let entries: [Entry]

    init(
        version: Int = currentVersion,
        importID: UUID,
        sourceDisplayName: String,
        createdAt: Date = .now,
        state: State,
        entries: [Entry]
    ) {
        self.version = version
        self.importID = importID
        self.sourceDisplayName = sourceDisplayName
        self.createdAt = createdAt
        self.state = state
        self.entries = entries
    }

    func validated() throws -> ManagedImportManifest {
        guard version == Self.currentVersion else {
            throw ManagedImportManifestError.unsupportedVersion(version)
        }

        var trackIDs: Set<UUID> = []
        var targetPaths: Set<String> = []
        for entry in entries {
            guard trackIDs.insert(entry.trackID).inserted else {
                throw ManagedImportManifestError.duplicateTrackID(
                    entry.trackID
                )
            }
            try validate(entry: entry)
            try insertTarget(
                entry.relativeMediaPath,
                into: &targetPaths
            )
            if let lyricPath = entry.lyric?.relativePath {
                try insertTarget(lyricPath, into: &targetPaths)
            }
            if let artworkPath = entry.artwork?.relativePath {
                try insertTarget(artworkPath, into: &targetPaths)
            }
        }
        return self
    }

    func advancing(
        to nextState: State,
        entries: [Entry]? = nil
    ) throws -> ManagedImportManifest {
        guard nextState == state || allowedNextStates.contains(nextState) else {
            throw ManagedImportManifestError.invalidTransition(
                from: state,
                to: nextState
            )
        }
        return try ManagedImportManifest(
            version: version,
            importID: importID,
            sourceDisplayName: sourceDisplayName,
            createdAt: createdAt,
            state: nextState,
            entries: entries ?? self.entries
        ).validated()
    }
}
