@testable import Cadence
import Foundation
import SwiftData
import Testing

struct ManagedArtworkEditingTests {
    @Test("Managed artwork replacement persists one current asset")
    func replaceAndRemoveArtwork() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Artwork-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let location = ManagedLibraryLocation(musicDirectory: root)
        try ManagedLibraryPackage(location: location)
            .bootstrapForConfirmedImport()
        let container = try artworkContainer()
        let context = ModelContext(container)
        let albumID = try #require(
            try context.fetch(FetchDescriptor<AlbumRecord>()).first?.id
        )
        let repository = LibraryRepository(modelContainer: container)
        let image = try artworkImage()

        let firstID = try await setAlbumArtwork(
            repository,
            albumID: albumID,
            image: image,
            scale: 1.25,
            location: location
        )
        let first = try #require(
            try await repository.artwork(id: firstID)
        )
        #expect(try location.resolve(relativePath: first.relativePath).exists)
        #expect(try await repository.album(id: albumID)?.customArtworkID == firstID)

        let replacementID = try await setAlbumArtwork(
            repository,
            albumID: albumID,
            image: image,
            scale: 1,
            location: location
        )
        #expect(replacementID != firstID)
        #expect(!location.packageURL.appending(path: first.relativePath).exists)
        #expect(
            try await repository.album(id: albumID)?.customArtworkID
                == replacementID
        )

        try await repository.removeArtwork(
            ownerKind: .album,
            ownerID: albumID,
            location: location
        )
        #expect(try await repository.album(id: albumID)?.customArtworkID == nil)
    }

    private func setAlbumArtwork(
        _ repository: LibraryRepository,
        albumID: UUID,
        image: Data,
        scale: CGFloat,
        location: ManagedLibraryLocation
    ) async throws -> UUID {
        try await repository.setArtwork(
            ManagedArtworkEditRequest(
                ownerKind: .album,
                ownerID: albumID,
                data: image,
                scale: scale,
                normalizedOffset: .zero
            ),
            location: location
        )
    }

    private func artworkImage() throws -> Data {
        try #require(
            Data(
                base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAA"
                    + "C0lEQVR42mP8/x8AAusB9WlRkwAAAABJRU5ErkJggg=="
            )
        )
    }

    private func artworkContainer() throws -> ModelContainer {
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let artist = ArtistRecord(name: "Artwork Artist")
        let album = AlbumRecord(title: "Artwork Album", artist: artist)
        context.insert(artist)
        context.insert(album)
        try context.save()
        return container
    }
}

private extension URL {
    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
