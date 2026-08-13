@testable import Cadence
import Foundation
import SwiftData
import Testing

struct LibraryTrashRecoveryTests {
    @Test("Trash writes recovery evidence before moving managed files")
    func manifestFailureDoesNotMoveManagedFile() async throws {
        let fixture = try TrashRecoveryFixture()
        defer { fixture.remove() }
        let operationID = UUID()
        let manifestURL = ManagedTrashManifestStore(location: fixture.location)
            .manifestURL(for: operationID)
        try FileManager.default.createDirectory(
            at: manifestURL,
            withIntermediateDirectories: true
        )
        let repository = LibraryRepository(modelContainer: fixture.container)

        await #expect(throws: (any Error).self) {
            try await repository.trash(
                targetKind: .track,
                targetID: fixture.trackID,
                location: fixture.location,
                operationID: operationID
            )
        }

        #expect(FileManager.default.fileExists(atPath: fixture.mediaURL.path))
        #expect(try await repository.tracksPage().items.count == 1)
    }

    @Test("Trash preserves its manifest when destination creation fails")
    func directoryCreationFailurePreservesManifest() async throws {
        let fixture = try TrashRecoveryFixture()
        defer { fixture.remove() }
        let operationID = UUID()
        let repository = LibraryRepository(modelContainer: fixture.container)

        do {
            _ = try await repository.trash(
                targetKind: .track,
                targetID: fixture.trackID,
                location: fixture.location,
                operationID: operationID,
                fileClient: .directoryCreationFailure
            )
            Issue.record("Expected directory creation to fail")
        } catch let error as LibraryTrashTransactionError {
            #expect(error.phase == .moveFiles)
            #expect(
                error.primaryFailure.contains(
                    "injected directory creation failure"
                )
            )
            #expect(error.recoveryDirectory.isPresent)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Trash retains manifest and reports every failed compensation")
    func partialMovePreservesRecoveryEvidence() async throws {
        let fixture = try TrashRecoveryFixture(fileCount: 2)
        defer { fixture.remove() }
        let operationID = UUID()
        let failures = TrashMoveFailureScript()
        let repository = LibraryRepository(modelContainer: fixture.container)

        do {
            _ = try await repository.trash(
                targetKind: .album,
                targetID: fixture.albumID,
                location: fixture.location,
                operationID: operationID,
                fileClient: failures.client
            )
            Issue.record("Expected the injected file move to fail")
        } catch let error as LibraryTrashTransactionError {
            requirePartialMoveFailure(error, operationID: operationID)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let recovery = try await repository.reconcileTrash(
            location: fixture.location
        )
        #expect(recovery.rolledBackOperationIDs == [operationID])
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.operationDirectory(operationID).path
            )
        )
        #expect(
            fixture.mediaURLs.allSatisfy {
                FileManager.default.fileExists(atPath: $0.path)
            }
        )
    }

    @Test("Restore cleanup failure is repaired during reconciliation")
    func restoreCleanupFailureIsReconciled() async throws {
        let fixture = try TrashRecoveryFixture()
        defer { fixture.remove() }
        let repository = LibraryRepository(modelContainer: fixture.container)
        let operationID = try await repository.trash(
            targetKind: .track,
            targetID: fixture.trackID,
            location: fixture.location
        )

        do {
            try await repository.restoreTrash(
                operationID: operationID,
                location: fixture.location,
                fileClient: .cleanupFailure
            )
            Issue.record("Expected the injected cleanup to fail")
        } catch let error as LibraryTrashTransactionError {
            #expect(error.phase == .cleanup)
            #expect(error.primaryFailure.contains("injected cleanup failure"))
            #expect(error.recoveryDirectory.isPresent)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let recovery = try await repository.reconcileTrash(
            location: fixture.location
        )
        #expect(recovery.cleanedOperationIDs == [operationID])
        #expect(try await repository.trashOperations().isEmpty)
        #expect(fixture.mediaURL.isPresent)
    }

    @Test("Restore reports catalog and file rollback failures together")
    func restorePreservesRollbackFailure() async throws {
        let fixture = try TrashRecoveryFixture()
        defer { fixture.remove() }
        let repository = LibraryRepository(modelContainer: fixture.container)
        let operationID = try await repository.trash(
            targetKind: .track,
            targetID: fixture.trackID,
            location: fixture.location
        )
        try fixture.insertConflictingTrack()

        do {
            try await repository.restoreTrash(
                operationID: operationID,
                location: fixture.location,
                fileClient: .restoreRollbackFailure
            )
            Issue.record("Expected catalog restoration to fail")
        } catch let error as LibraryTrashTransactionError {
            #expect(error.phase == .restoreCatalog)
            #expect(error.compensationFailures.count == 1)
            #expect(
                error.compensationFailures[0]
                    .contains("injected restore rollback failure")
            )
            #expect(error.recoveryDirectory.isPresent)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Corrupt Trash records fail closed instead of disappearing")
    func corruptRecordIsReported() async throws {
        let fixture = try TrashRecoveryFixture()
        defer { fixture.remove() }
        let repository = LibraryRepository(modelContainer: fixture.container)
        _ = try await repository.trash(
            targetKind: .track,
            targetID: fixture.trackID,
            location: fixture.location
        )
        let context = ModelContext(fixture.container)
        let record = try #require(
            try context.fetch(FetchDescriptor<TrashOperationRecord>()).first
        )
        record.targetIDsData = Data("not-json".utf8)
        try context.save()

        await #expect(throws: (any Error).self) {
            _ = try await repository.trashOperations()
        }
    }

    @Test("A committed Trash record fails closed when its file is missing")
    func committedRecordRequiresEveryManagedFile() async throws {
        let fixture = try TrashRecoveryFixture()
        defer { fixture.remove() }
        let repository = LibraryRepository(modelContainer: fixture.container)
        let operationID = try await repository.trash(
            targetKind: .track,
            targetID: fixture.trackID,
            location: fixture.location
        )
        let trashedURL = try fixture.location.resolve(
            relativePath: "Trash/\(operationID)/Media/\(fixture.trackID).flac"
        )
        try FileManager.default.removeItem(at: trashedURL)

        await #expect(throws: LibraryTrashTransactionError.self) {
            _ = try await repository.reconcileTrash(
                location: fixture.location
            )
        }
        #expect(fixture.operationDirectory(operationID).isPresent)
    }

    @Test("Trash refuses to commit when a managed source file is missing")
    func missingSourceFilePreventsTrashCommit() async throws {
        let fixture = try TrashRecoveryFixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.mediaURL)
        let repository = LibraryRepository(modelContainer: fixture.container)

        await #expect(throws: LibraryTrashTransactionError.self) {
            _ = try await repository.trash(
                targetKind: .track,
                targetID: fixture.trackID,
                location: fixture.location
            )
        }

        #expect(try await repository.tracksPage().items.count == 1)
        #expect(try await repository.trashOperations().isEmpty)
    }
}

private struct TrashRecoveryFixture {
    private struct Seed {
        let albumID: UUID
        let trackIDs: [UUID]
        let mediaURLs: [URL]
    }

    let root: URL
    let location: ManagedLibraryLocation
    let container: ModelContainer
    let albumID: UUID
    let trackID: UUID
    let mediaURL: URL
    let trackIDs: [UUID]
    let mediaURLs: [URL]

    init(fileCount: Int = 1) throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Trash-Recovery-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        location = ManagedLibraryLocation(musicDirectory: root)
        try ManagedLibraryPackage(location: location)
            .bootstrapForConfirmedImport()
        container = try LibraryContainerFactory.inMemory()
        let seed = try Self.seed(
            container: container,
            location: location,
            fileCount: fileCount
        )
        albumID = seed.albumID
        trackIDs = seed.trackIDs
        mediaURLs = seed.mediaURLs
        trackID = try #require(trackIDs.first)
        mediaURL = try #require(mediaURLs.first)
    }

    private static func seed(
        container: ModelContainer,
        location: ManagedLibraryLocation,
        fileCount: Int
    ) throws -> Seed {
        let context = ModelContext(container)
        let artist = ArtistRecord(
            name: "Recovery Artist",
            trackCount: fileCount,
            albumCount: 1
        )
        let album = AlbumRecord(
            title: "Recovery Album",
            artist: artist,
            trackCount: fileCount
        )
        var seededTrackIDs: [UUID] = []
        var seededMediaURLs: [URL] = []
        context.insert(artist)
        context.insert(album)
        for index in 0 ..< fileCount {
            let id = UUID()
            let relativePath = "Media/\(id.uuidString).flac"
            let track = TrackRecord(
                id: id,
                originalFilename: "Recovery \(index).flac",
                title: "Recovery \(index)",
                duration: 1,
                codec: "FLAC",
                container: "flac",
                sampleRate: 44100,
                channelCount: 2,
                contentHash: String(repeating: "\(index)", count: 64),
                relativeMediaPath: relativePath,
                importSessionID: UUID(),
                artist: artist,
                album: album
            )
            context.insert(track)
            let url = try location.resolve(relativePath: relativePath)
            try Data("audio-\(index)".utf8).write(to: url)
            seededTrackIDs.append(id)
            seededMediaURLs.append(url)
        }
        try context.save()
        return Seed(
            albumID: album.id,
            trackIDs: seededTrackIDs,
            mediaURLs: seededMediaURLs
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func operationDirectory(_ operationID: UUID) -> URL {
        ManagedLibraryPackage(location: location)
            .trashDirectoryURL.appending(
                path: operationID.uuidString,
                directoryHint: .isDirectory
            )
    }

    func insertConflictingTrack() throws {
        let context = ModelContext(container)
        context.insert(
            TrackRecord(
                id: trackID,
                originalFilename: "Conflict.flac",
                title: "Conflict",
                duration: 1,
                codec: "FLAC",
                container: "flac",
                sampleRate: 44100,
                channelCount: 2,
                contentHash: String(repeating: "f", count: 64),
                relativeMediaPath: "Media/conflict.flac",
                importSessionID: UUID()
            )
        )
        try context.save()
    }
}

private func requirePartialMoveFailure(
    _ error: LibraryTrashTransactionError,
    operationID: UUID
) {
    #expect(error.operationID == operationID)
    #expect(error.phase == .moveFiles)
    #expect(error.primaryFailure.contains("injected move failure"))
    #expect(error.compensationFailures.count == 1)
    #expect(
        error.compensationFailures[0]
            .contains("injected rollback failure")
    )
    #expect(error.recoveryDirectory.isPresent)
    #expect(
        error.recoveryDirectory.appending(path: "manifest.json").isPresent
    )
}
