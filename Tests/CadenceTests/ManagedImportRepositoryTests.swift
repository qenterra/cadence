@testable import Cadence
import Foundation
import SwiftData
import Testing

struct ManagedImportRepositoryTests {
    @Test("A manifest commits one import session and reuses artist and album")
    func commitsManifest() async throws {
        let container = try LibraryContainerFactory.inMemory()
        let repository = LibraryRepository(modelContainer: container)
        let first = makeManifest(
            importID: UUID(),
            entries: [
                makeEntry(
                    title: "First Signal",
                    hashSeed: "1",
                    withLyrics: true
                ),
                makeEntry(
                    title: "Second Signal",
                    hashSeed: "2"
                ),
            ]
        )

        let firstResult = try await repository.commitImport(first)
        let second = makeManifest(
            importID: UUID(),
            entries: [
                makeEntry(
                    title: "Third Signal",
                    hashSeed: "3"
                ),
            ]
        )
        let secondResult = try await repository.commitImport(second)

        #expect(firstResult.importedTrackIDs == first.entries.map(\.trackID))
        #expect(firstResult.lyricsLinked == 1)
        #expect(secondResult.importedTrackIDs == second.entries.map(\.trackID))
        try assertCommittedRecords(
            container: container,
            manifests: [first, second]
        )
    }

    private func assertCommittedRecords(
        container: ModelContainer,
        manifests: [ManagedImportManifest]
    ) throws {
        let context = ModelContext(container)
        let artists = try context.fetch(FetchDescriptor<ArtistRecord>())
        let albums = try context.fetch(FetchDescriptor<AlbumRecord>())
        let tracks = try context.fetch(FetchDescriptor<TrackRecord>())
        let lyrics = try context.fetch(FetchDescriptor<LyricRecord>())
        let sessions = try context.fetch(
            FetchDescriptor<ImportSessionRecord>()
        )
        #expect(artists.count == 1)
        #expect(artists.first?.trackCount == 3)
        #expect(artists.first?.albumCount == 1)
        #expect(albums.count == 1)
        #expect(albums.first?.trackCount == 3)
        #expect(albums.first?.totalDuration == 540)
        #expect(tracks.count == 3)
        #expect(lyrics.count == 1)
        #expect(sessions.count == 2)
        #expect(sessions.allSatisfy { $0.state == .storeCommitted })
        #expect(
            Set(tracks.map(\.relativeMediaPath))
                == Set(
                    manifests.flatMap(\.entries).map(\.relativeMediaPath)
                )
        )
    }

    @Test("Duplicate content rejects the whole manifest")
    func duplicateContentRollsBack() async throws {
        let container = try LibraryContainerFactory.inMemory()
        let repository = LibraryRepository(modelContainer: container)
        let hash = String(repeating: "a", count: 64)
        let first = makeManifest(
            importID: UUID(),
            entries: [
                makeEntry(title: "Committed", contentHash: hash),
            ]
        )
        _ = try await repository.commitImport(first)
        let duplicate = makeManifest(
            importID: UUID(),
            entries: [
                makeEntry(title: "Would Be Inserted", hashSeed: "4"),
                makeEntry(title: "Duplicate", contentHash: hash),
            ]
        )

        await #expect(throws: ManagedImportStoreError.self) {
            try await repository.commitImport(duplicate)
        }

        let context = ModelContext(container)
        let tracks = try context.fetch(FetchDescriptor<TrackRecord>())
        let sessions = try context.fetch(
            FetchDescriptor<ImportSessionRecord>()
        )
        #expect(tracks.count == 1)
        #expect(sessions.count == 1)
    }

    @Test("Imported session results are bounded and ordered")
    func importedSessionResults() async throws {
        let container = try LibraryContainerFactory.inMemory()
        let repository = LibraryRepository(modelContainer: container)
        let importID = UUID()
        let manifest = makeManifest(
            importID: importID,
            entries: (0 ..< 4).map { index in
                makeEntry(
                    title: "Track \(index)",
                    hashSeed: "\(index + 5)"
                )
            }
        )
        _ = try await repository.commitImport(manifest)

        let tracks = try await repository.importedTracks(
            importID: importID,
            limit: 2
        )

        #expect(tracks.count == 2)
        #expect(tracks.map(\.title) == ["Track 0", "Track 1"])
    }

    private func makeManifest(
        importID: UUID,
        entries: [ManagedImportManifest.Entry]
    ) -> ManagedImportManifest {
        ManagedImportManifest(
            importID: importID,
            sourceDisplayName: "Lossless",
            state: .filesCommitted,
            entries: entries
        )
    }

    private func makeEntry(
        title: String,
        hashSeed: String = "a",
        contentHash: String? = nil,
        withLyrics: Bool = false
    ) -> ManagedImportManifest.Entry {
        let trackID = UUID()
        return ManagedImportManifest.Entry(
            trackID: trackID,
            sourceAudioPath: "/Source/\(title).flac",
            sourceLyricPath: withLyrics ? "/Source/\(title).lrc" : nil,
            originalFilename: "\(title).flac",
            originalExtension: "flac",
            metadata: ManagedImportManifest.Metadata(
                title: title,
                artist: "North Assembly",
                album: "Signals",
                year: 2026,
                trackNumber: nil,
                discNumber: nil,
                duration: 180,
                codec: "FLAC",
                container: "FLAC",
                sampleRate: 48000,
                channelCount: 2,
                bitrate: nil,
                bitDepth: 24,
                spatialFormat: .stereo
            ),
            expectedAudioHash: contentHash
                ?? String(repeating: hashSeed, count: 64),
            sizeInBytes: 1024,
            relativeMediaPath: "Media/\(trackID.uuidString).flac",
            lyric: withLyrics
                ? ManagedImportManifest.LyricAsset(
                    relativePath: "Lyrics/\(trackID.uuidString).lrc",
                    contentHash: String(repeating: "f", count: 64),
                    timingStatus: "synchronized"
                )
                : nil,
            state: .copied,
            failureReason: nil
        )
    }
}
