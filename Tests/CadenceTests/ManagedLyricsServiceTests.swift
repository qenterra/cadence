@testable import Cadence
import Foundation
import SwiftData
import Testing

struct ManagedLyricsServiceTests {
    @Test("A partial document saves to managed LRC and SwiftData")
    func savesPartialDocument() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let document = LyricDocument(
            trackID: fixture.trackID,
            lines: [
                LyricLine(text: "First", startTime: 1),
                LyricLine(text: "Second"),
            ],
            metadataLines: ["[ar:North Assembly]"]
        )

        try await fixture.service.save(document)

        let target = fixture.package.lyricURL(
            trackID: fixture.trackID
        )
        let source = try String(contentsOf: target, encoding: .utf8)
        let metadata = try await fixture.repository.lyricMetadata(
            trackID: fixture.trackID
        )
        let reloaded = try await fixture.service.load(
            trackID: fixture.trackID
        )

        #expect(
            source
                == """
                [ar:North Assembly]
                [00:01.000]First
                Second

                """
        )
        #expect(metadata?.timingStatus == .partiallySynchronized)
        #expect(
            metadata?.contentHash
                == ContentHasher().sha256(of: Data(source.utf8))
        )
        #expect(reloaded?.trackID == .managed(fixture.trackID))
        #expect(reloaded?.metadataLines == ["[ar:North Assembly]"])
        #expect(reloaded?.lines.map(\.text) == ["First", "Second"])
    }

    @Test("Replacing and clearing lyrics converge file and metadata")
    func replacesAndClears() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        try await fixture.service.save(
            document(
                trackID: fixture.trackID,
                text: "First",
                time: 1
            )
        )
        try await fixture.service.save(
            document(
                trackID: fixture.trackID,
                text: "Replacement",
                time: nil
            )
        )

        let target = fixture.package.lyricURL(
            trackID: fixture.trackID
        )
        #expect(
            try String(contentsOf: target, encoding: .utf8)
                == "Replacement\n"
        )
        #expect(
            try await fixture.repository.lyricMetadata(
                trackID: fixture.trackID
            )?.timingStatus == .unsynchronized
        )

        try await fixture.service.save(
            LyricDocument(
                trackID: fixture.trackID,
                lines: [LyricLine(text: "")]
            )
        )

        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(
            try await fixture.repository.lyricMetadata(
                trackID: fixture.trackID
            ) == nil
        )
    }

    @Test("Repository failure restores the previous managed file")
    func repositoryFailureRollsBack() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let missingTrackID = UUID()
        let target = fixture.package.lyricURL(trackID: missingTrackID)
        let original = Data("Original\n".utf8)
        try original.write(to: target)

        await #expect(throws: ManagedLyricRepositoryError.self) {
            try await fixture.service.save(
                self.document(
                    trackID: missingTrackID,
                    text: "Would replace",
                    time: 2
                )
            )
        }

        #expect(try Data(contentsOf: target) == original)
    }

    private func document(
        trackID: UUID,
        text: String,
        time: TimeInterval?
    ) -> LyricDocument {
        LyricDocument(
            trackID: trackID,
            lines: [LyricLine(text: text, startTime: time)]
        )
    }
}

@MainActor
struct LibraryStoreLyricsProjectionTests {
    @Test("Saving lyrics publishes each synchronization transition once")
    func savePublishesSynchronizationTransitions() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let store = LibraryStore()
        try await store.attach(
            repository: fixture.repository,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let window = try #require(store.allTracksWindow)
        await configure(window, store: store)
        let trackIndex = try #require(window.index(ofTrackID: fixture.trackID))
        let initialRevision = window.revision

        #expect(window.track(at: trackIndex)?.hasSynchronizedLyrics == false)

        try await store.saveLyrics(
            LyricDocument(
                trackID: fixture.trackID,
                lines: [LyricLine(text: "Synchronized", startTime: 1)]
            )
        )

        #expect(window.track(at: trackIndex)?.hasSynchronizedLyrics == true)
        #expect(window.revision == initialRevision + 1)

        let clearedDocument = LyricDocument(
            trackID: fixture.trackID,
            lines: [LyricLine(text: "")]
        )
        try await store.saveLyrics(clearedDocument)

        #expect(window.track(at: trackIndex)?.hasSynchronizedLyrics == false)
        #expect(window.revision == initialRevision + 2)

        try await store.saveLyrics(clearedDocument)

        #expect(window.revision == initialRevision + 2)
    }

    @Test("Loading an orphaned lyric publishes the repaired projection once")
    func orphanedLoadPublishesRepair() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let store = LibraryStore()
        try await store.attach(
            repository: fixture.repository,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let window = try #require(store.allTracksWindow)
        await configure(window, store: store)
        let trackIndex = try #require(window.index(ofTrackID: fixture.trackID))
        let initialRevision = window.revision
        try Data("[00:02.000]Recovered orphan\n".utf8).write(
            to: fixture.package.lyricURL(trackID: fixture.trackID)
        )

        _ = try await store.lyricsDocument(trackID: fixture.trackID)

        #expect(window.track(at: trackIndex)?.hasSynchronizedLyrics == true)
        #expect(window.revision == initialRevision + 1)

        _ = try await store.lyricsDocument(trackID: fixture.trackID)

        #expect(window.revision == initialRevision + 1)
    }

    @Test("Installed-file recovery publishes the repaired projection once")
    func installedRecoveryPublishesRepair() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let store = LibraryStore()
        try await store.attach(
            repository: fixture.repository,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let window = try #require(store.allTracksWindow)
        await configure(window, store: store)
        let trackIndex = try #require(window.index(ofTrackID: fixture.trackID))
        let initialRevision = window.revision
        let operationID = UUID()
        let data = Data("[00:01.000]Recovered\n".utf8)
        try data.write(
            to: fixture.package.lyricURL(trackID: fixture.trackID)
        )
        try ManagedLyricEditManifestStore(package: fixture.package).save(
            ManagedLyricEditManifest(
                operationID: operationID,
                trackID: fixture.trackID,
                targetRelativePath: "Lyrics/\(fixture.trackID.uuidString).lrc",
                previousContentHash: nil,
                newContentHash: ContentHasher().sha256(of: data),
                newTimingStatus: .synchronized,
                state: .fileInstalled
            )
        )

        let result = try await store.recoverLyricsEdits()

        #expect(result.recoveredOperationIDs == [operationID])
        #expect(result.affectedTrackIDs == [fixture.trackID])
        #expect(window.track(at: trackIndex)?.hasSynchronizedLyrics == true)
        #expect(window.revision == initialRevision + 1)

        let emptyResult = try await store.recoverLyricsEdits()

        #expect(emptyResult == .empty)
        #expect(window.revision == initialRevision + 1)
    }

    @Test("Save publishes tracks repaired by its internal recovery")
    func savePublishesInternalRecoveryTracks() async throws {
        let fixture = try ManagedLyricsFixture(trackCount: 2)
        defer { fixture.remove() }
        let savedTrackID = try #require(fixture.additionalTrackIDs.first)
        let store = LibraryStore()
        try await store.attach(
            repository: fixture.repository,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let window = try #require(store.allTracksWindow)
        await configure(window, store: store)
        let recoveredIndex = try #require(
            window.index(ofTrackID: fixture.trackID)
        )
        let savedIndex = try #require(window.index(ofTrackID: savedTrackID))
        let initialRevision = window.revision
        let recoveryData = Data("[00:01.000]Recovered\n".utf8)
        try recoveryData.write(
            to: fixture.package.lyricURL(trackID: fixture.trackID)
        )
        try ManagedLyricEditManifestStore(package: fixture.package).save(
            ManagedLyricEditManifest(
                operationID: UUID(),
                trackID: fixture.trackID,
                targetRelativePath: "Lyrics/\(fixture.trackID.uuidString).lrc",
                previousContentHash: nil,
                newContentHash: ContentHasher().sha256(of: recoveryData),
                newTimingStatus: .synchronized,
                state: .fileInstalled
            )
        )

        try await store.saveLyrics(
            LyricDocument(
                trackID: savedTrackID,
                lines: [LyricLine(text: "Saved", startTime: 2)]
            )
        )

        #expect(
            window.track(at: recoveredIndex)?.hasSynchronizedLyrics == true
        )
        #expect(window.track(at: savedIndex)?.hasSynchronizedLyrics == true)
        #expect(window.revision == initialRevision + 2)
    }

    @Test("Durable lyric save survives an unavailable projection refresh")
    func saveProjectionRefreshIsBestEffort() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let store = LibraryStore()
        try await store.attach(
            repository: fixture.repository,
            package: fixture.package
        )
        store.repository = nil

        try await store.saveLyrics(
            LyricDocument(
                trackID: fixture.trackID,
                lines: [LyricLine(text: "Durable", startTime: 1)]
            )
        )

        #expect(
            try await fixture.repository.lyricMetadata(
                trackID: fixture.trackID
            )?.timingStatus == .synchronized
        )
    }

    @Test("Recovery result survives an unavailable projection refresh")
    func recoveryProjectionRefreshIsBestEffort() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let store = LibraryStore()
        try await store.attach(
            repository: fixture.repository,
            package: fixture.package
        )
        let operationID = UUID()
        let data = Data("[00:01.000]Recovered\n".utf8)
        try data.write(
            to: fixture.package.lyricURL(trackID: fixture.trackID)
        )
        try ManagedLyricEditManifestStore(package: fixture.package).save(
            ManagedLyricEditManifest(
                operationID: operationID,
                trackID: fixture.trackID,
                targetRelativePath: "Lyrics/\(fixture.trackID.uuidString).lrc",
                previousContentHash: nil,
                newContentHash: ContentHasher().sha256(of: data),
                newTimingStatus: .synchronized,
                state: .fileInstalled
            )
        )
        store.repository = nil

        let result = try await store.recoverLyricsEdits()

        #expect(result.recoveredOperationIDs == [operationID])
        #expect(result.affectedTrackIDs == [fixture.trackID])
        #expect(
            try await fixture.repository.lyricMetadata(
                trackID: fixture.trackID
            )?.timingStatus == .synchronized
        )
    }

    @Test("Ordinary lyric load does not require projection refresh")
    func ordinaryLoadSkipsProjectionRefresh() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        try await fixture.service.save(
            LyricDocument(
                trackID: fixture.trackID,
                lines: [LyricLine(text: "Existing", startTime: 1)]
            )
        )
        let store = LibraryStore()
        try await store.attach(
            repository: fixture.repository,
            package: fixture.package
        )
        store.repository = nil

        let document = try await store.lyricsDocument(
            trackID: fixture.trackID
        )

        #expect(document?.lines.map(\.text) == ["Existing"])
    }

    private func configure(
        _ window: LibraryTrackWindow,
        store: LibraryStore
    ) async {
        await window.configure(
            totalCount: store.catalogCounts.liveTrackCount,
            query: store.trackQuery,
            contentVersion: store.allTracksWindowContentVersion
        )
    }
}

struct ManagedLyricsRecoveryTests {
    @Test("Recovery finalizes an installed file idempotently")
    func recoversInstalledFile() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let source = "[00:01.000]Recovered\n"
        let data = Data(source.utf8)
        let operationID = UUID()
        let relativePath = "Lyrics/\(fixture.trackID.uuidString).lrc"
        try data.write(
            to: fixture.package.lyricURL(trackID: fixture.trackID)
        )
        let manifest = ManagedLyricEditManifest(
            operationID: operationID,
            trackID: fixture.trackID,
            targetRelativePath: relativePath,
            previousContentHash: nil,
            newContentHash: ContentHasher().sha256(of: data),
            newTimingStatus: .synchronized,
            state: .fileInstalled
        )
        try ManagedLyricEditManifestStore(
            package: fixture.package
        ).save(manifest)

        let first = try await fixture.service.recover()
        let second = try await fixture.service.recover()

        #expect(first.recoveredOperationIDs == [operationID])
        #expect(second == .empty)
        #expect(
            try await fixture.repository.lyricMetadata(
                trackID: fixture.trackID
            )?.timingStatus == .synchronized
        )
    }

    @Test("Prepared recovery restores the previous file")
    func preparedRecoveryRollsBack() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let store = ManagedLyricEditManifestStore(
            package: fixture.package
        )
        let operationID = UUID()
        let target = fixture.package.lyricURL(trackID: fixture.trackID)
        let previous = Data("Previous\n".utf8)
        try Data("Interrupted\n".utf8).write(to: target)
        let manifest = ManagedLyricEditManifest(
            operationID: operationID,
            trackID: fixture.trackID,
            targetRelativePath: "Lyrics/\(fixture.trackID.uuidString).lrc",
            previousContentHash: ContentHasher().sha256(of: previous),
            newContentHash: ContentHasher().sha256(
                of: Data("Interrupted\n".utf8)
            ),
            newTimingStatus: .unsynchronized,
            state: .prepared
        )
        try store.save(manifest)
        try previous.write(to: store.previousURL(operationID))

        let result = try await fixture.service.recover()

        #expect(result.rolledBackOperationIDs == [operationID])
        #expect(try Data(contentsOf: target) == previous)
        #expect(
            try await fixture.repository.lyricMetadata(
                trackID: fixture.trackID
            ) == nil
        )
    }

    @Test("Prepared recovery preserves an untouched previous target")
    func preparedRecoveryBeforeMovePreservesTarget() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let store = ManagedLyricEditManifestStore(
            package: fixture.package
        )
        let operationID = UUID()
        let target = fixture.package.lyricURL(trackID: fixture.trackID)
        let previous = Data("Still original\n".utf8)
        try previous.write(to: target)
        let manifest = ManagedLyricEditManifest(
            operationID: operationID,
            trackID: fixture.trackID,
            targetRelativePath: "Lyrics/\(fixture.trackID.uuidString).lrc",
            previousContentHash: ContentHasher().sha256(of: previous),
            newContentHash: ContentHasher().sha256(
                of: Data("Never installed\n".utf8)
            ),
            newTimingStatus: .unsynchronized,
            state: .prepared
        )
        try store.save(manifest)

        let result = try await fixture.service.recover()

        #expect(result.rolledBackOperationIDs == [operationID])
        #expect(try Data(contentsOf: target) == previous)
    }

    @Test("Loading an orphaned canonical file repairs SwiftData metadata")
    func orphanedFileRepairsMetadata() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let target = fixture.package.lyricURL(trackID: fixture.trackID)
        try Data("[00:02.000]Recovered orphan\n".utf8).write(
            to: target
        )

        let loadResult = try await fixture.service.loadResult(
            trackID: fixture.trackID
        )
        let secondLoadResult = try await fixture.service.loadResult(
            trackID: fixture.trackID
        )

        #expect(loadResult.document?.lines.map(\.text) == ["Recovered orphan"])
        #expect(loadResult.didRepairMetadata)
        #expect(!secondLoadResult.didRepairMetadata)
        #expect(
            try await fixture.repository.lyricMetadata(
                trackID: fixture.trackID
            )?.timingStatus == .synchronized
        )
    }

    @Test("Service rejects invalid timing before touching managed files")
    func invalidTimingDoesNotWrite() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let target = fixture.package.lyricURL(trackID: fixture.trackID)

        await #expect(throws: ManagedLyricsServiceError.self) {
            try await fixture.service.save(
                LyricDocument(
                    trackID: fixture.trackID,
                    lines: [
                        LyricLine(text: "Too late", startTime: 181),
                    ]
                )
            )
        }

        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(
            try await fixture.repository.lyricMetadata(
                trackID: fixture.trackID
            ) == nil
        )
    }

    @Test("Malformed manifests are quarantined")
    func malformedManifestIsQuarantined() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let store = ManagedLyricEditManifestStore(
            package: fixture.package
        )
        let operationID = UUID()
        let operationURL = store.operationURL(operationID)
        try FileManager.default.createDirectory(
            at: operationURL,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(
            to: store.manifestURL(operationID)
        )

        let result = try await fixture.service.recover()

        #expect(result == .empty)
        #expect(
            FileManager.default.fileExists(
                atPath: store.quarantineRootURL.appending(
                    path: operationID.uuidString
                ).path
            )
        )
        #expect(!FileManager.default.fileExists(atPath: operationURL.path))
    }

    @Test("Installed file hash mismatch is quarantined without deletion")
    func hashMismatchIsQuarantined() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let store = ManagedLyricEditManifestStore(
            package: fixture.package
        )
        let operationID = UUID()
        let target = fixture.package.lyricURL(trackID: fixture.trackID)
        let actualData = Data("Externally changed\n".utf8)
        try actualData.write(to: target)
        try store.save(
            ManagedLyricEditManifest(
                operationID: operationID,
                trackID: fixture.trackID,
                targetRelativePath: "Lyrics/\(fixture.trackID.uuidString).lrc",
                previousContentHash: nil,
                newContentHash: ContentHasher().sha256(
                    of: Data("Expected\n".utf8)
                ),
                newTimingStatus: .unsynchronized,
                state: .fileInstalled
            )
        )

        await #expect(
            throws: ManagedLyricsServiceError.self
        ) {
            try await fixture.service.recover()
        }

        #expect(try Data(contentsOf: target) == actualData)
        #expect(
            FileManager.default.fileExists(
                atPath: store.quarantineRootURL.appending(
                    path: operationID.uuidString
                ).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: store.operationURL(operationID).path
            )
        )
    }
}
