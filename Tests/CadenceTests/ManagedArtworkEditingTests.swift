@testable import Cadence
import Foundation
import SwiftData
import Testing

struct ManagedArtworkEditingTests {
    @Test("Managed artwork replacement persists one current asset")
    func replaceAndRemoveArtwork() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }

        let firstID = try await fixture.service.setArtwork(
            fixture.request(scale: 1.25)
        )
        let first = try #require(
            try await fixture.repository.artwork(id: firstID)
        )
        #expect(try fixture.location.resolve(relativePath: first.relativePath).exists)
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == firstID
        )

        let replacementID = try await fixture.service.setArtwork(
            fixture.request(scale: 1)
        )
        #expect(replacementID != firstID)
        #expect(!fixture.package.packageURL.appending(path: first.relativePath).exists)
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == replacementID
        )

        try await fixture.service.removeArtwork(
            ownerKind: .album,
            ownerID: fixture.albumID
        )
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == nil
        )
    }

    @Test("Playlist and Smart Collection artwork use the managed edit pipeline")
    func collectionOwnerParity() async throws {
        for ownerKind in [
            ArtworkOwnerKind.playlist,
            ArtworkOwnerKind.smartCollection,
        ] {
            let fixture = try ManagedArtworkFixture()
            defer { fixture.remove() }
            let ownerID = try #require(fixture.ownerID(for: ownerKind))

            let artworkID = try await fixture.service.setArtwork(
                fixture.request(ownerKind: ownerKind, ownerID: ownerID)
            )
            #expect(
                try await fixture.repository.artworkEditSnapshot(
                    ownerKind: ownerKind,
                    ownerID: ownerID
                )?.id == artworkID
            )

            try await fixture.service.removeArtwork(
                ownerKind: ownerKind,
                ownerID: ownerID
            )
            #expect(
                try await fixture.repository.artworkEditSnapshot(
                    ownerKind: ownerKind,
                    ownerID: ownerID
                ) == nil
            )
        }
    }
}

struct ManagedArtworkRecoveryTests {
    @Test("Recovery commits an installed artwork file idempotently")
    func recoversInstalledArtwork() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let manifest = try fixture.manifest(state: .fileInstalled)
        try fixture.installNewFile(for: manifest)
        try fixture.store.save(manifest)

        let first = try await fixture.service.recover()
        let second = try await fixture.service.recover()

        #expect(first.recoveredOperationIDs == [manifest.operationID])
        #expect(second == .empty)
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == manifest.newArtwork?.id
        )
    }

    @Test("Prepared recovery removes staged work and preserves metadata")
    func preparedRecoveryRollsBack() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let manifest = try fixture.manifest(state: .prepared)
        try fixture.store.save(manifest)
        try fixture.image.write(
            to: fixture.store.stagedURL(manifest.operationID)
        )

        let result = try await fixture.service.recover()

        #expect(result.rolledBackOperationIDs == [manifest.operationID])
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == nil
        )
        #expect(!fixture.store.operationURL(manifest.operationID).exists)
    }

    @Test("Committed recovery cleans the previous artwork file")
    func committedRecoveryCleansPreviousFile() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let previousID = try await fixture.service.setArtwork(
            fixture.request(scale: 1)
        )
        let previous = try #require(
            try await fixture.repository.artworkEditSnapshot(
                ownerKind: .album,
                ownerID: fixture.albumID
            )
        )
        let previousURL = try fixture.location.resolve(
            relativePath: previous.relativeOriginalPath
        )
        #expect(previous.id == previousID)
        #expect(previousURL.exists)

        let installed = try fixture.manifest(
            state: .fileInstalled,
            previousArtwork: previous
        )
        try fixture.installNewFile(for: installed)
        try await fixture.repository.applyArtworkEdit(installed)
        let committed = installed.advancing(to: .metadataCommitted)
        try fixture.store.save(committed)

        let result = try await fixture.service.recover()

        #expect(result.recoveredOperationIDs == [committed.operationID])
        #expect(!previousURL.exists)
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == committed.newArtwork?.id
        )
    }

    @Test("Hash mismatch is quarantined without deleting the unexpected file")
    func hashMismatchIsQuarantined() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let manifest = try fixture.manifest(state: .fileInstalled)
        let target = try #require(manifest.newArtwork).relativeOriginalPath
        let targetURL = try fixture.location.resolve(relativePath: target)
        try Data("unexpected".utf8).write(to: targetURL)
        try fixture.store.save(manifest)

        await #expect(throws: ManagedArtworkEditError.self) {
            try await fixture.service.recover()
        }

        #expect(try Data(contentsOf: targetURL) == Data("unexpected".utf8))
        #expect(
            fixture.store.quarantineRootURL.appending(
                path: manifest.operationID.uuidString
            ).exists
        )
    }
}

private struct ManagedArtworkFixture {
    let root: URL
    let location: ManagedLibraryLocation
    let package: ManagedLibraryPackage
    let repository: LibraryRepository
    let service: ManagedArtworkService
    let store: ManagedArtworkEditManifestStore
    let albumID: UUID
    let playlistID: UUID
    let smartCollectionID: UUID
    let image: Data

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Artwork-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        location = ManagedLibraryLocation(musicDirectory: root)
        package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let artist = ArtistRecord(name: "Artwork Artist")
        let album = AlbumRecord(title: "Artwork Album", artist: artist)
        let playlist = PlaylistRecord(name: "Artwork Playlist")
        let smartCollection = SmartCollectionRecord(
            name: "Artwork Mix",
            ruleData: Data("fixture".utf8),
            sortDescriptorRawValue: "canonical:ascending",
            playbackPreferenceRawValue: "ordered"
        )
        context.insert(artist)
        context.insert(album)
        context.insert(playlist)
        context.insert(smartCollection)
        try context.save()
        albumID = album.id
        playlistID = playlist.id
        smartCollectionID = smartCollection.id
        repository = LibraryRepository(modelContainer: container)
        service = ManagedArtworkService(
            package: package,
            repository: repository
        )
        store = ManagedArtworkEditManifestStore(package: package)
        image = try #require(
            Data(
                base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAA"
                    + "C0lEQVR42mP8/x8AAusB9WlRkwAAAABJRU5ErkJggg=="
            )
        )
    }

    func request(scale: CGFloat) -> ManagedArtworkEditRequest {
        request(
            ownerKind: .album,
            ownerID: albumID,
            scale: scale
        )
    }

    func request(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID,
        scale: CGFloat = 1
    ) -> ManagedArtworkEditRequest {
        ManagedArtworkEditRequest(
            ownerKind: ownerKind,
            ownerID: ownerID,
            data: image,
            scale: scale,
            normalizedOffset: .zero
        )
    }

    func ownerID(
        for ownerKind: ArtworkOwnerKind
    ) -> UUID? {
        switch ownerKind {
        case .album:
            albumID
        case .playlist:
            playlistID
        case .smartCollection:
            smartCollectionID
        case .artist, .track:
            nil
        }
    }

    func manifest(
        state: ManagedArtworkEditManifest.State,
        previousArtwork: ManagedArtworkDescriptor? = nil
    ) throws -> ManagedArtworkEditManifest {
        let payload = try #require(
            MetadataReader().artworkPayload(data: image)
        )
        let id = UUID()
        return ManagedArtworkEditManifest(
            operationID: UUID(),
            ownerKind: .album,
            ownerID: albumID,
            mutationKind: .set,
            previousArtwork: previousArtwork,
            newArtwork: ManagedArtworkDescriptor(
                id: id,
                ownerKind: .album,
                ownerID: albumID,
                relativeOriginalPath: "Artwork/Original/\(id.uuidString)."
                    + payload.metadata.format,
                relativeThumbnailPath: nil,
                format: payload.metadata.format,
                pixelWidth: payload.metadata.pixelWidth,
                pixelHeight: payload.metadata.pixelHeight,
                cropScale: 1,
                normalizedOffsetX: 0,
                normalizedOffsetY: 0,
                contentHash: payload.metadata.contentHash,
                revision: 0
            ),
            state: state
        )
    }

    func installNewFile(for manifest: ManagedArtworkEditManifest) throws {
        let artwork = try #require(manifest.newArtwork)
        try image.write(
            to: location.resolve(relativePath: artwork.relativeOriginalPath)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private extension URL {
    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
