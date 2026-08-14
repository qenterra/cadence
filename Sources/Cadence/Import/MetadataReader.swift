import AVFoundation
import CoreMedia
import Foundation

/// Reads source metadata without mutating the selected audio file.
///
/// Metadata and artwork calls may run independently. Implementations must keep
/// both results tied to the exact URL and surface unreadable audio as an error.
protocol AudioMetadataReading: Sendable {
    func read(url: URL) async throws -> ScannedAudioMetadata
    func readEmbeddedArtwork(url: URL) async throws -> EmbeddedArtworkPayload?
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
    case unreadableMetadata(String, detail: String)
    case unreadableEmbeddedArtwork(String, detail: String)

    var errorDescription: String? {
        switch self {
        case let .noAudioTrack(path):
            "No audio track was found in \(path)."
        case let .unavailableAudioFormat(path):
            "Audio properties are unavailable for \(path)."
        case let .unreadableMetadata(path, detail):
            "Metadata could not be read from \(path): \(detail)"
        case let .unreadableEmbeddedArtwork(path, detail):
            "Embedded artwork could not be read from \(path): \(detail)"
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

    private struct TextMetadata {
        let display: AudioDisplayMetadata
        let artist: String
        let artists: [String]
        let albumArtist: String?
        let year: Int?
        let trackNumber: Int?
        let discNumber: Int?
    }

    func read(
        url: URL
    ) async throws -> ScannedAudioMetadata {
        do {
            return try await readAsset(url: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MetadataReaderError {
            throw error
        } catch {
            throw MetadataReaderError.unreadableMetadata(
                url.lastPathComponent,
                detail: error.localizedDescription
            )
        }
    }

    private func readAsset(
        url: URL
    ) async throws -> ScannedAudioMetadata {
        try Task.checkCancellation()

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        async let commonMetadata = asset.load(.commonMetadata)
        async let containerMetadata = asset.load(.metadata)
        let metadata = try await commonMetadata + containerMetadata
        let values = MetadataValueResolver(items: metadata)
        let embeddedLyrics = try await EmbeddedLyricsReader().read(
            items: metadata
        )
        let sourceMetadata = try await SourceMetadataSnapshot.capture(
            items: metadata
        )
        let properties = try await audioProperties(
            asset: asset,
            url: url
        )
        let artwork = try await embeddedArtwork(
            metadataItems: metadata,
            url: url
        )
        let text = try await textMetadata(values: values, url: url)
        return ScannedAudioMetadata(
            title: text.display.title,
            artist: text.artist,
            album: text.display.album,
            artists: text.artists,
            albumArtist: text.albumArtist,
            year: text.year,
            trackNumber: text.trackNumber,
            discNumber: text.discNumber,
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

    private func textMetadata(
        values: MetadataValueResolver,
        url: URL
    ) async throws -> TextMetadata {
        let display = try await displayMetadata(values: values, url: url)
        let sourceArtistValues = try await values.strings(
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
        let albumArtistValues = try await values.strings(
            rawKeys: ["ALBUMARTIST", "ALBUMARTISTS", "TPE2"]
        )
        let albumArtist = ArtistCreditParser().parse(
            values: albumArtistValues,
            fallback: artists[0]
        ).first
        let date = try await values.string(
            commonIdentifier: .commonIdentifierCreationDate,
            rawKeys: ["DATE", "YEAR", "TDRC", "TYER"]
        )
        let trackNumber = try await values.integer(
            rawKeys: ["TRACK", "TRACKNUMBER", "TRCK"]
        )
        let discNumber = try await values.integer(
            rawKeys: ["DISC", "DISCNUMBER", "TPOS"]
        )

        return TextMetadata(
            display: display,
            artist: artistDisplay,
            artists: artists,
            albumArtist: albumArtistValues.isEmpty ? nil : albumArtist,
            year: year(from: date),
            trackNumber: trackNumber,
            discNumber: discNumber
        )
    }

    func readEmbeddedArtwork(
        url: URL
    ) async throws -> EmbeddedArtworkPayload? {
        do {
            if url.pathExtension.lowercased() == "flac" {
                return try await embeddedArtwork(
                    metadataItems: [],
                    url: url
                )
            }
            let asset = AVURLAsset(url: url)
            async let common = asset.load(.commonMetadata)
            async let container = asset.load(.metadata)
            let metadata = try await common + container
            return try await embeddedArtwork(
                metadataItems: metadata,
                url: url
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MetadataReaderError {
            throw error
        } catch {
            throw MetadataReaderError.unreadableEmbeddedArtwork(
                url.lastPathComponent,
                detail: error.localizedDescription
            )
        }
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
        let estimatedDataRate = try await track.load(.estimatedDataRate)
        return AudioProperties(
            codec: fourCC(stream.mFormatID),
            sampleRate: stream.mSampleRate,
            channelCount: channels,
            bitrate: estimatedDataRate > 0
                ? Int(estimatedDataRate.rounded())
                : nil,
            bitDepth: stream.mBitsPerChannel > 0
                ? Int(stream.mBitsPerChannel)
                : nil,
            spatialFormat: channels > 2 ? .multichannel : .stereo
        )
    }

    private func displayMetadata(
        values: MetadataValueResolver,
        url: URL
    ) async throws -> AudioDisplayMetadata {
        let title = try await values.string(
            commonIdentifier: .commonIdentifierTitle,
            rawKeys: ["TITLE", "TIT2"]
        ) ?? url.deletingPathExtension().lastPathComponent
        let artist = try await values.string(
            commonIdentifier: .commonIdentifierArtist,
            rawKeys: ["ARTIST", "PERFORMER", "TPE1"]
        ) ?? "Unknown Artist"
        let album = try await values.string(
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
