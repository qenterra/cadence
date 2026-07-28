import AVFoundation
@testable import Cadence
import Foundation
import Testing

struct MetadataReaderTests {
    @Test("Vorbis comments provide display and ordering metadata")
    func vorbisMetadata() async {
        let resolver = MetadataValueResolver(
            items: [
                metadataItem(key: "TITLE", value: "BLUE"),
                metadataItem(key: "ARTIST", value: "Billie Eilish"),
                metadataItem(
                    key: "ALBUM",
                    value: "HIT ME HARD AND SOFT"
                ),
                metadataItem(key: "DATE", value: "2024"),
                metadataItem(key: "TRACKNUMBER", value: "10/10"),
                metadataItem(key: "DISCNUMBER", value: "1/1"),
            ]
        )

        #expect(
            await resolver.string(rawKeys: ["TITLE"])
                == "BLUE"
        )
        #expect(
            await resolver.string(rawKeys: ["ARTIST"])
                == "Billie Eilish"
        )
        #expect(
            await resolver.string(rawKeys: ["ALBUM"])
                == "HIT ME HARD AND SOFT"
        )
        #expect(await resolver.integer(rawKeys: ["TRACKNUMBER"]) == 10)
        #expect(await resolver.integer(rawKeys: ["DISCNUMBER"]) == 1)
    }

    @Test("A real WAV exposes technical properties and safe display fallbacks")
    func wavFallbacks() async throws {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "Untitled Signal-\(UUID().uuidString).wav"
        )
        try writeSilentWAV(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let metadata = try await MetadataReader().read(url: url)

        #expect(metadata.title.hasPrefix("Untitled Signal-"))
        #expect(metadata.artist == "Unknown Artist")
        #expect(metadata.album == "Unknown Album")
        #expect(metadata.container == "WAV")
        #expect(metadata.sampleRate == 44100)
        #expect(metadata.channelCount == 2)
        #expect(metadata.duration > 0.09)
        #expect(metadata.duration < 0.11)
    }

    @Test("FLAC picture blocks expose validated embedded artwork")
    func flacEmbeddedArtwork() async throws {
        let png = try #require(
            Data(
                base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAA"
                    + "C0lEQVR42mP8/x8AAusB9WlRkwAAAABJRU5ErkJggg=="
            )
        )
        let url = FileManager.default.temporaryDirectory.appending(
            path: "Embedded-Artwork-\(UUID().uuidString).flac"
        )
        try writeFLACPicture(png, to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let artwork = try #require(
            await MetadataReader().readEmbeddedArtwork(url: url)
        )

        #expect(artwork.data == png)
        #expect(artwork.metadata.format == "png")
        #expect(artwork.metadata.pixelWidth == 1)
        #expect(artwork.metadata.pixelHeight == 1)
        #expect(
            artwork.metadata.contentHash
                == ContentHasher().sha256(of: png)
        )
    }

    private func writeSilentWAV(
        to url: URL
    ) throws {
        let format = try #require(
            AVAudioFormat(
                standardFormatWithSampleRate: 44100,
                channels: 2
            )
        )
        let frameCount: AVAudioFrameCount = 4410
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            )
        )
        buffer.frameLength = frameCount

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings
        )
        try file.write(from: buffer)
    }

    private func writeFLACPicture(
        _ artwork: Data,
        to url: URL
    ) throws {
        let mime = Data("image/png".utf8)
        var block = Data()
        appendUInt32(3, to: &block)
        appendUInt32(UInt32(mime.count), to: &block)
        block.append(mime)
        appendUInt32(0, to: &block)
        appendUInt32(1, to: &block)
        appendUInt32(1, to: &block)
        appendUInt32(32, to: &block)
        appendUInt32(0, to: &block)
        appendUInt32(UInt32(artwork.count), to: &block)
        block.append(artwork)

        var file = Data("fLaC".utf8)
        let length = block.count
        file.append(0x86)
        file.append(UInt8((length >> 16) & 0xFF))
        file.append(UInt8((length >> 8) & 0xFF))
        file.append(UInt8(length & 0xFF))
        file.append(block)
        try file.write(to: url)
    }

    private func appendUInt32(
        _ value: UInt32,
        to data: inout Data
    ) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private func metadataItem(
        key: String,
        value: String
    ) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = AVMetadataKeySpace(rawValue: "vorb")
        item.key = key as NSString
        item.value = value as NSString
        return item
    }
}
