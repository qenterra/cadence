import AVFoundation
import CoreMedia
import Foundation

protocol AudioMetadataReading: Sendable {
    func read(url: URL) async throws -> ScannedAudioMetadata
    func readEmbeddedArtwork(url: URL) async -> EmbeddedArtworkPayload?
}

struct EmbeddedArtworkMetadata: Codable, Equatable, Sendable {
    let contentHash: String
    let format: String
    let pixelWidth: Int
    let pixelHeight: Int
}

struct EmbeddedArtworkPayload: Sendable {
    let metadata: EmbeddedArtworkMetadata
    let data: Data
}

private struct AudioDisplayMetadata {
    let title: String
    let artist: String
    let album: String
}

struct ScannedAudioMetadata: Codable, Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let artists: [String]
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
    var embeddedArtwork: EmbeddedArtworkMetadata?
    let embeddedLyrics: EmbeddedLyricsPayload?
    let sourceMetadata: SourceMetadataSnapshot?

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
        embeddedArtwork: EmbeddedArtworkMetadata? = nil,
        embeddedLyrics: EmbeddedLyricsPayload? = nil,
        sourceMetadata: SourceMetadataSnapshot? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artists = ArtistCreditParser().parse(
            values: artists ?? [artist],
            fallback: artist
        )
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
        self.embeddedArtwork = embeddedArtwork
        self.embeddedLyrics = embeddedLyrics
        self.sourceMetadata = sourceMetadata
    }
}

enum MetadataReaderError: Error, LocalizedError, Sendable {
    case noAudioTrack(String)
    case unavailableAudioFormat(String)

    var errorDescription: String? {
        switch self {
        case let .noAudioTrack(path):
            "No audio track was found in \(path)."
        case let .unavailableAudioFormat(path):
            "Audio properties are unavailable for \(path)."
        }
    }
}

struct MetadataReader: Sendable {
    private struct AudioProperties {
        let codec: String
        let sampleRate: Double
        let channelCount: Int
        let bitrate: Int?
        let bitDepth: Int?
        let spatialFormat: StoredSpatialFormat
    }

    func read(
        url: URL
    ) async throws -> ScannedAudioMetadata {
        try Task.checkCancellation()

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        async let commonMetadata = asset.load(.commonMetadata)
        async let containerMetadata = asset.load(.metadata)
        let metadata = try await commonMetadata + containerMetadata
        let values = MetadataValueResolver(items: metadata)
        let embeddedLyrics = await EmbeddedLyricsReader().read(
            items: metadata
        )
        let sourceMetadata = await SourceMetadataSnapshot.capture(
            items: metadata
        )
        let properties = try await audioProperties(
            asset: asset,
            url: url
        )
        let artwork = await embeddedArtwork(
            asset: asset,
            metadataItems: metadata,
            url: url
        )
        let display = await displayMetadata(values: values, url: url)
        let sourceArtistValues = await values.strings(
            commonIdentifier: .commonIdentifierArtist,
            rawKeys: ["ARTIST", "PERFORMER", "TPE1"]
        )
        let artistDisplay = sourceArtistValues.isEmpty
            ? display.artist
            : sourceArtistValues.joined(separator: ", ")
        let artists = ArtistCreditParser().parse(
            values: sourceArtistValues,
            fallback: display.artist
        )
        let albumArtistValues = await values.strings(
            rawKeys: ["ALBUMARTIST", "ALBUMARTISTS", "TPE2"]
        )
        let albumArtist = ArtistCreditParser().parse(
            values: albumArtistValues,
            fallback: artists[0]
        ).first
        let date = await values.string(
            commonIdentifier: .commonIdentifierCreationDate,
            rawKeys: ["DATE", "YEAR", "TDRC", "TYER"]
        )
        let trackNumber = await values.integer(
            rawKeys: ["TRACK", "TRACKNUMBER", "TRCK"]
        )
        let discNumber = await values.integer(
            rawKeys: ["DISC", "DISCNUMBER", "TPOS"]
        )

        return ScannedAudioMetadata(
            title: display.title,
            artist: artistDisplay,
            album: display.album,
            artists: artists,
            albumArtist: albumArtistValues.isEmpty ? nil : albumArtist,
            year: year(from: date),
            trackNumber: trackNumber,
            discNumber: discNumber,
            duration: max(duration.seconds, 0),
            codec: properties.codec,
            container: containerName(for: url),
            sampleRate: properties.sampleRate,
            channelCount: properties.channelCount,
            bitrate: properties.bitrate,
            bitDepth: properties.bitDepth,
            spatialFormat: properties.spatialFormat,
            embeddedArtwork: artwork?.metadata,
            embeddedLyrics: embeddedLyrics,
            sourceMetadata: sourceMetadata
        )
    }

    func readEmbeddedArtwork(
        url: URL
    ) async -> EmbeddedArtworkPayload? {
        let asset = AVURLAsset(url: url)
        let common = await (try? asset.load(.commonMetadata)) ?? []
        let container = await (try? asset.load(.metadata)) ?? []
        return await embeddedArtwork(
            asset: asset,
            metadataItems: common + container,
            url: url
        )
    }

    private func audioProperties(
        asset: AVURLAsset,
        url: URL
    ) async throws -> AudioProperties {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw MetadataReaderError.noAudioTrack(url.path)
        }
        let descriptions = try await track.load(.formatDescriptions)
        guard
            let description = descriptions.first,
            let pointer = CMAudioFormatDescriptionGetStreamBasicDescription(
                description
            )
        else {
            throw MetadataReaderError.unavailableAudioFormat(url.path)
        }

        let stream = pointer.pointee
        let channels = Int(stream.mChannelsPerFrame)
        let estimatedDataRate = try? await track.load(.estimatedDataRate)
        return AudioProperties(
            codec: fourCC(stream.mFormatID),
            sampleRate: stream.mSampleRate,
            channelCount: channels,
            bitrate: estimatedDataRate.map { Int($0.rounded()) },
            bitDepth: stream.mBitsPerChannel > 0
                ? Int(stream.mBitsPerChannel)
                : nil,
            spatialFormat: channels > 2 ? .multichannel : .stereo
        )
    }

    private func displayMetadata(
        values: MetadataValueResolver,
        url: URL
    ) async -> AudioDisplayMetadata {
        let title = await values.string(
            commonIdentifier: .commonIdentifierTitle,
            rawKeys: ["TITLE", "TIT2"]
        ) ?? url.deletingPathExtension().lastPathComponent
        let artist = await values.string(
            commonIdentifier: .commonIdentifierArtist,
            rawKeys: ["ARTIST", "PERFORMER", "TPE1"]
        ) ?? "Unknown Artist"
        let album = await values.string(
            commonIdentifier: .commonIdentifierAlbumName,
            rawKeys: ["ALBUM", "TALB"]
        ) ?? "Unknown Album"
        return AudioDisplayMetadata(
            title: title,
            artist: artist,
            album: album
        )
    }

    private func year(
        from value: String?
    ) -> Int? {
        guard let value else {
            return nil
        }
        return Int(value.prefix(4))
    }

    private func containerName(
        for url: URL
    ) -> String {
        switch url.pathExtension.lowercased() {
        case "aif", "aiff":
            "AIFF"
        case "m4a":
            "M4A"
        default:
            url.pathExtension.uppercased()
        }
    }

    private func fourCC(
        _ value: FourCharCode
    ) -> String {
        let characters = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        let text = String(bytes: characters, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else {
            return "Unknown"
        }
        return text
    }
}

extension MetadataReader: AudioMetadataReading {}
