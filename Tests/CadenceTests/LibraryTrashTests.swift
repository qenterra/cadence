@testable import Cadence
import Foundation
import SwiftData
import Testing

struct LibraryTrashTests {
    @Test("Version two Trash manifests remain readable after credit migration")
    func readsVersionTwoManifest() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Trash-V2-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let location = ManagedLibraryLocation(musicDirectory: root)
        try ManagedLibraryPackage(location: location)
            .bootstrapForConfirmedImport()
        let operationID = UUID()
        let manifest = ManagedTrashManifest(
            version: 2,
            operationID: operationID,
            targetKind: .track,
            targetID: nil,
            createdAt: .now,
            artists: [],
            albums: [],
            tracks: [],
            artistCredits: nil,
            lyrics: [],
            artworks: [],
            tagAssignments: [],
            tagExclusions: [],
            playlistEntries: nil,
            originalRelativePaths: []
        )
        let store = ManagedTrashManifestStore(location: location)
        try store.write(manifest)

        #expect(try store.read(operationID: operationID).version == 2)
    }

    @Test("Deleting one credited artist keeps the shared track and restores the credit")
    func trashSharedPrimaryArtist() async throws {
        let fixture = try SharedArtistTrashFixture()
        defer { fixture.remove() }
        let repository = LibraryRepository(modelContainer: fixture.container)

        let operationID = try await repository.trash(
            targetKind: .artist,
            targetID: fixture.primaryArtistID,
            location: fixture.location
        )

        let context = ModelContext(fixture.container)
        #expect(fixture.mediaURL.fileExists)
        #expect(try context.fetch(FetchDescriptor<TrackRecord>()).count == 1)
        #expect(
            try context.fetch(FetchDescriptor<ArtistRecord>()).map(\.name)
                == ["темный принц"]
        )
        let remainingArtist = try #require(
            try context.fetch(FetchDescriptor<ArtistRecord>()).first
        )
        #expect(
            try context.fetch(FetchDescriptor<TrackArtistCreditRecord>())
                .map(\.artistID) == [remainingArtist.id]
        )
        #expect(
            try context.fetch(FetchDescriptor<TrackRecord>()).first?.artist?.name
                == "темный принц"
        )
        #expect(
            try context.fetch(FetchDescriptor<AlbumRecord>()).first?.artist?.name
                == "темный принц"
        )

        try await repository.restoreTrash(
            operationID: operationID,
            location: fixture.location
        )

        try verifyRestoredSharedArtist(context: context, fixture: fixture)
    }

    @Test("A captured confirmation still deletes after the dialog binding clears pending state")
    @MainActor
    func capturedDeletionConfirmation() async throws {
        let fixture = try DeletionHandoffFixture()
        defer { fixture.remove() }
        await fixture.session.store.loadInitialLibrary()
        let model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .unavailable("Not used by this test."),
            librarySession: fixture.session
        )
        model.requestLibraryDeletion(
            kind: .album,
            id: fixture.albumID,
            title: "Captured Album"
        )
        let captured = try #require(model.pendingLibraryDeletion)

        model.cancelLibraryDeletion()
        await model.confirmLibraryDeletion(captured)

        #expect(model.pendingLibraryDeletion == nil)
        #expect(fixture.session.store.albums.isEmpty)
        #expect(fixture.session.store.tracks.isEmpty)
        #expect(fixture.session.store.trashOperations.count == 1)
    }

    @Test("An album can be trashed, restored, and deleted permanently")
    func trashAlbum() async throws {
        let fixture = try TrashFixture()
        defer { fixture.remove() }

        let repository = LibraryRepository(
            modelContainer: fixture.container
        )
        let operationID = try await repository.trash(
            targetKind: .album,
            targetID: fixture.albumID,
            location: fixture.location
        )

        let operations = try await repository.trashOperations(
            location: fixture.location
        )
        let trashed = try #require(operations.first)
        #expect(trashed.id == operationID)
        #expect(trashed.targetKind == .album)
        #expect(trashed.displayTitle == "Trash Album")
        #expect(trashed.displaySubtitle == "Trash Artist")
        #expect(Set(trashed.targetIDs) == Set(fixture.trackIDs))
        #expect(trashed.relativePaths.count == fixture.managedPaths.count)
        #expect(try await repository.tracksPage().items.isEmpty)
        #expect(try await repository.albumsPage().items.isEmpty)
        #expect(try await repository.artistsPage().items.isEmpty)
        #expect(
            try ModelContext(fixture.container).fetch(
                FetchDescriptor<PlaylistEntryRecord>()
            ).isEmpty
        )
        try fixture.requireMovedFiles(operationID: operationID)

        try await repository.restoreTrash(
            operationID: operationID,
            location: fixture.location
        )
        #expect(try await repository.trashOperations().isEmpty)
        #expect(try await repository.tracksPage().items.count == 3)
        #expect(try await repository.albumsPage().items.count == 1)
        #expect(try await repository.artistsPage().items.count == 1)
        #expect(
            try await repository.playlistTracks(
                playlistID: fixture.playlistID
            ).map(\.id) == fixture.trackIDs
        )
        try fixture.requireRestoredFiles(operationID: operationID)
        try fixture.requireRestoredMetadata()

        let secondOperationID = try await repository.trash(
            targetKind: .album,
            targetID: fixture.albumID,
            location: fixture.location
        )
        try await repository.emptyTrash(location: fixture.location)
        #expect(try await repository.trashOperations().isEmpty)
        #expect(!fixture.operationDirectory(secondOperationID).fileExists)
    }

    @Test("Multiple selected tracks move to Trash in one bulk request")
    func trashSelectedTracks() async throws {
        let fixture = try TrashFixture()
        defer { fixture.remove() }
        let repository = LibraryRepository(
            modelContainer: fixture.container
        )

        let operationIDs = try await repository.trashTracks(
            targetIDs: Array(fixture.trackIDs.prefix(2)),
            location: fixture.location
        )

        #expect(operationIDs.count == 2)
        #expect(try await repository.tracksPage().items.count == 1)
        #expect(try await repository.trashOperations().count == 2)
    }
}
