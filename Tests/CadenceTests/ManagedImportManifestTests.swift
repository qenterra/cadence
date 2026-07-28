@testable import Cadence
import Foundation
import Testing

struct ManagedImportManifestTests {
    @Test("Version one round trips every recovery-critical field")
    func roundTrip() throws {
        let manifest = fixtureManifest()
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(
            ManagedImportManifest.self,
            from: data
        )

        #expect(decoded == manifest)
        #expect(try decoded.validated() == manifest)
    }

    @Test("Unknown versions and non-monotonic transitions are rejected")
    func versionAndTransitions() throws {
        let unknown = ManagedImportManifest(
            version: 999,
            importID: UUID(),
            sourceDisplayName: "Unknown",
            createdAt: .now,
            state: .prepared,
            entries: []
        )

        #expect(throws: ManagedImportManifestError.self) {
            try unknown.validated()
        }

        let copied = try fixtureManifest().advancing(to: .copied)
        #expect(throws: ManagedImportManifestError.self) {
            try copied.advancing(to: .prepared)
        }
        #expect(throws: ManagedImportManifestError.self) {
            try copied.advancing(to: .complete)
        }
    }

    @Test("Duplicate targets and paths outside managed ownership are rejected")
    func ownershipValidation() {
        let first = fixtureEntry()
        let duplicate = ManagedImportManifest.Entry(
            trackID: UUID(),
            sourceAudioPath: "/source/Other.flac",
            sourceLyricPath: nil,
            originalFilename: "Other.flac",
            originalExtension: "flac",
            metadata: fixtureMetadata(title: "Other"),
            expectedAudioHash: String(repeating: "b", count: 64),
            sizeInBytes: 42,
            relativeMediaPath: first.relativeMediaPath,
            lyric: nil,
            state: .pending,
            failureReason: nil
        )
        let duplicateManifest = ManagedImportManifest(
            importID: UUID(),
            sourceDisplayName: "Duplicates",
            state: .prepared,
            entries: [first, duplicate]
        )

        #expect(throws: ManagedImportManifestError.self) {
            try duplicateManifest.validated()
        }

        var escaped = first
        escaped.relativeMediaPath = "../outside.flac"
        let escapedManifest = ManagedImportManifest(
            importID: UUID(),
            sourceDisplayName: "Escape",
            state: .prepared,
            entries: [escaped]
        )
        #expect(throws: ManagedImportManifestError.self) {
            try escapedManifest.validated()
        }
    }

    private func fixtureManifest() -> ManagedImportManifest {
        ManagedImportManifest(
            importID: UUID(
                uuidString: "6B3285F5-DDA4-4B2A-BB63-0E7375868AAC"
            )!,
            sourceDisplayName: "Lossless",
            createdAt: Date(timeIntervalSince1970: 123),
            state: .prepared,
            entries: [fixtureEntry()]
        )
    }

    private func fixtureEntry() -> ManagedImportManifest.Entry {
        let trackID = UUID(
            uuidString: "7EBCF36A-AF4E-4E1B-9F4D-09850FBFB0EF"
        )!
        return ManagedImportManifest.Entry(
            trackID: trackID,
            sourceAudioPath: "/source/Midnight Static.flac",
            sourceLyricPath: "/source/Midnight Static.lrc",
            originalFilename: "Midnight Static.flac",
            originalExtension: "flac",
            metadata: fixtureMetadata(title: "Midnight Static"),
            expectedAudioHash: String(repeating: "a", count: 64),
            sizeInBytes: 42,
            relativeMediaPath: "Media/\(trackID.uuidString).flac",
            lyric: ManagedImportManifest.LyricAsset(
                relativePath: "Lyrics/\(trackID.uuidString).lrc",
                contentHash: nil,
                timingStatus: nil
            ),
            state: .pending,
            failureReason: nil
        )
    }

    private func fixtureMetadata(
        title: String
    ) -> ManagedImportManifest.Metadata {
        ManagedImportManifest.Metadata(
            title: title,
            artist: "North Assembly",
            album: "Signals After Dark",
            year: 2026,
            trackNumber: 1,
            discNumber: 1,
            duration: 277,
            codec: "FLAC",
            container: "FLAC",
            sampleRate: 96000,
            channelCount: 2,
            bitrate: 2_400_000,
            bitDepth: 24,
            spatialFormat: .stereo
        )
    }
}
