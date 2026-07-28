@testable import Cadence
import Foundation
import Testing

struct ManagedLibraryImporterTests {
    @Test("Confirmed import copies UUID assets, commits metadata, and preserves sources")
    func importsManagedAssets() async throws {
        let fixture = try ImportFixture()
        defer { fixture.remove() }
        let audioData = Data("lossless-audio".utf8)
        let lyricData = Data("[00:01.00]First line\n[00:04.50]Second line".utf8)
        let audioURL = try fixture.writeSource(
            name: "Midnight Static.flac",
            data: audioData
        )
        let lyricURL = try fixture.writeSource(
            name: "Midnight Static.lrc",
            data: lyricData
        )
        let candidate = try await fixture.candidate(
            audioURL: audioURL,
            lyricURL: lyricURL
        )
        let destination = ManagedLibraryImportDestination(
            package: fixture.package,
            repository: nil
        )
        let importer = ManagedLibraryImporter(
            destination: destination,
            availableCapacity: { _ in .max }
        )

        let completion = try await importer.importCandidates(
            [candidate],
            includedIDs: [candidate.id],
            sourceDisplayName: "Lossless"
        )

        try await assertSuccessfulImport(
            SuccessfulImportContext(
                fixture: fixture,
                candidate: candidate,
                completion: completion,
                audioData: audioData,
                lyricData: lyricData,
                audioURL: audioURL,
                lyricURL: lyricURL,
                destination: destination
            )
        )
    }

    @Test("A changed LRC is skipped without blocking valid audio")
    func skipsChangedLyrics() async throws {
        let fixture = try ImportFixture()
        defer { fixture.remove() }
        let audioURL = try fixture.writeSource(
            name: "Signal.flac",
            data: Data("audio".utf8)
        )
        let lyricURL = try fixture.writeSource(
            name: "Signal.lrc",
            data: Data("[00:01.00]Valid".utf8)
        )
        let candidate = try await fixture.candidate(
            audioURL: audioURL,
            lyricURL: lyricURL
        )
        try Data("not an lrc".utf8).write(to: lyricURL)
        let destination = ManagedLibraryImportDestination(
            package: fixture.package,
            repository: nil
        )
        let importer = ManagedLibraryImporter(
            destination: destination,
            availableCapacity: { _ in .max }
        )

        let completion = try await importer.importCandidates(
            [candidate],
            includedIDs: [candidate.id],
            sourceDisplayName: "Changed lyrics"
        )

        #expect(completion.importedTrackIDs == [candidate.id])
        #expect(completion.lyricsLinked == 0)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.package.lyricURL(
                    trackID: candidate.id
                ).path
            )
        )
    }

    @Test("Capacity is checked before Cadence.library is created")
    func capacityFailureDoesNotCreateLibrary() async throws {
        let fixture = try ImportFixture()
        defer { fixture.remove() }
        let audioURL = try fixture.writeSource(
            name: "Large.flac",
            data: Data("audio".utf8)
        )
        let candidate = try await fixture.candidate(audioURL: audioURL)
        let destination = ManagedLibraryImportDestination(
            package: fixture.package,
            repository: nil
        )
        let importer = ManagedLibraryImporter(
            destination: destination,
            availableCapacity: { _ in 0 }
        )

        await #expect(throws: ManagedLibraryImportError.self) {
            try await importer.importCandidates(
                [candidate],
                includedIDs: [candidate.id],
                sourceDisplayName: "No room"
            )
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.package.packageURL.path
            )
        )
    }

    @Test("Recovery is idempotent after every durable import boundary")
    func recoversEveryFailurePoint() async throws {
        for point in ManagedImportFailurePoint.allCases {
            try await assertRecovery(at: point)
        }
    }

    @Test("A target collision never deletes the pre-existing asset")
    func preservesTargetCollision() async throws {
        let fixture = try ImportFixture()
        defer { fixture.remove() }
        let audioURL = try fixture.writeSource(
            name: "Collision.flac",
            data: Data("source".utf8)
        )
        let candidate = try await fixture.candidate(audioURL: audioURL)
        try fixture.package.bootstrapForConfirmedImport()
        let targetURL = try fixture.package.mediaURL(
            trackID: candidate.id,
            originalExtension: "flac"
        )
        let existingData = Data("already-owned".utf8)
        try existingData.write(to: targetURL)
        let destination = ManagedLibraryImportDestination(
            package: fixture.package,
            repository: nil
        )
        let importer = ManagedLibraryImporter(
            destination: destination,
            availableCapacity: { _ in .max }
        )

        await #expect(throws: ManagedLibraryImportError.self) {
            try await importer.importCandidates(
                [candidate],
                includedIDs: [candidate.id],
                sourceDisplayName: "Collision"
            )
        }

        #expect(try Data(contentsOf: targetURL) == existingData)
        #expect(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.package.stagingDirectoryURL.path
            ).isEmpty
        )
    }
}

private extension ManagedLibraryImporterTests {
    func assertSuccessfulImport(
        _ context: SuccessfulImportContext
    ) async throws {
        let managedAudio = try context.fixture.package.location.resolve(
            relativePath: "Media/\(context.candidate.id.uuidString).flac"
        )
        let managedLyric = try context.fixture.package.location.resolve(
            relativePath: "Lyrics/\(context.candidate.id.uuidString).lrc"
        )
        #expect(try Data(contentsOf: context.audioURL) == context.audioData)
        #expect(try Data(contentsOf: context.lyricURL) == context.lyricData)
        #expect(try Data(contentsOf: managedAudio) == context.audioData)
        #expect(try Data(contentsOf: managedLyric) == context.lyricData)
        #expect(context.completion.importedTrackIDs == [context.candidate.id])
        #expect(context.completion.lyricsLinked == 1)
        #expect(context.completion.importedByteCount == context.audioData.count)
        #expect(
            try FileManager.default.contentsOfDirectory(
                atPath: context.fixture.package.stagingDirectoryURL.path
            ).isEmpty
        )
        let repository = try #require(
            await context.destination.currentRepository()
        )
        let tracks = try await repository.importedTracks(
            importID: context.completion.importID
        )
        #expect(tracks.map(\.title) == ["Midnight Static"])
    }

    func assertRecovery(
        at point: ManagedImportFailurePoint
    ) async throws {
        let fixture = try ImportFixture()
        defer { fixture.remove() }
        let audioURL = try fixture.writeSource(
            name: "\(point.rawValue).flac",
            data: Data("audio-\(point.rawValue)".utf8)
        )
        let candidate = try await fixture.candidate(audioURL: audioURL)
        let destination = ManagedLibraryImportDestination(
            package: fixture.package,
            repository: nil
        )
        let importer = crashingImporter(
            destination: destination,
            point: point
        )
        await #expect(throws: ManagedImportInjectedFailure.self) {
            try await importer.importCandidates(
                [candidate],
                includedIDs: [candidate.id],
                sourceDisplayName: point.rawValue
            )
        }
        let store = ManagedImportManifestStore(package: fixture.package)
        let manifest = try #require(
            try store.loadRecoverableManifests().first
        )
        let recovery = ManagedLibraryImportRecovery(destination: destination)
        let result = try await recovery.recover()
        #expect(try await recovery.recover() == .empty)
        #expect(try store.loadRecoverableManifests().isEmpty)
        try await assertRecoveryResult(
            RecoveryResultContext(
                result: result,
                point: point,
                manifest: manifest,
                candidate: candidate,
                destination: destination,
                fixture: fixture
            )
        )
    }

    func crashingImporter(
        destination: ManagedLibraryImportDestination,
        point: ManagedImportFailurePoint
    ) -> ManagedLibraryImporter {
        ManagedLibraryImporter(
            destination: destination,
            failureInjector: ManagedImportFailureInjector { reached in
                if reached == point {
                    throw InjectedImportFailure.crash
                }
            },
            availableCapacity: { _ in .max }
        )
    }

    func assertRecoveryResult(
        _ context: RecoveryResultContext
    ) async throws {
        let shouldCommit = context.point == .afterFilesCommitted
            || context.point == .afterStoreCommitted
        if shouldCommit {
            #expect(
                context.result.recoveredImportIDs
                    == [context.manifest.importID]
            )
            let repository = try #require(
                await context.destination.currentRepository()
            )
            #expect(
                try await repository.importSessionState(
                    importID: context.manifest.importID
                ) == .complete
            )
            #expect(
                try await repository.importedTracks(
                    importID: context.manifest.importID
                ).map(\.id) == [context.candidate.id]
            )
        } else {
            #expect(
                context.result.discardedImportIDs
                    == [context.manifest.importID]
            )
            let finalURL = try context.fixture.package.location.resolve(
                relativePath: context.manifest.entries[0].relativeMediaPath
            )
            #expect(!FileManager.default.fileExists(atPath: finalURL.path))
        }
    }
}
