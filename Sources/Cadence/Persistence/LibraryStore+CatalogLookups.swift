import Foundation

extension LibraryStore {
    func renameTrack(
        id: UUID,
        title: String
    ) async throws -> LibraryTrackProjection {
        guard let repository else {
            throw CatalogRenameError.itemUnavailable
        }
        let renamed = try await repository.renameTrack(id: id, title: title)
        await loadInitialLibrary()
        return renamed
    }

    func renameAlbum(
        id: UUID,
        title: String
    ) async throws -> LibraryAlbumProjection {
        guard let repository else {
            throw CatalogRenameError.itemUnavailable
        }
        let renamed = try await repository.renameAlbum(id: id, title: title)
        await loadInitialLibrary()
        return renamed
    }

    func renameArtist(
        id: UUID,
        name: String
    ) async throws -> LibraryArtistProjection {
        guard let repository else {
            throw CatalogRenameError.itemUnavailable
        }
        let renamed = try await repository.renameArtist(id: id, name: name)
        await loadInitialLibrary()
        return renamed
    }

    func artist(id: UUID) async -> LibraryArtistProjection? {
        try? await repository?.artist(id: id)
    }

    func album(id: UUID) async -> LibraryAlbumProjection? {
        try? await repository?.album(id: id)
    }

    func tracks(albumID: UUID) async -> [LibraryTrackProjection] {
        await (
            try? repository?.albumTracksInPlaybackOrder(
                albumID: albumID
            )
        ) ?? []
    }

    func tracks(artistID: UUID) async -> [LibraryTrackProjection] {
        guard let repository else {
            return []
        }
        var projections: [LibraryTrackProjection] = []
        var cursor: LibraryPageCursor?
        do {
            repeat {
                let page = try await repository.tracksPage(
                    query: LibraryTrackQuery(scope: .artist(artistID)),
                    after: cursor
                )
                projections.append(contentsOf: page.items)
                cursor = page.nextCursor
            } while cursor != nil
            return deduplicatedTracks(projections)
        } catch {
            return []
        }
    }

    func albums(artistID: UUID) async -> [LibraryAlbumProjection] {
        await (try? repository?.albums(artistID: artistID)) ?? []
    }

    func artistReleaseSections(
        artistID: UUID
    ) async -> ArtistReleaseSections {
        await (
            try? repository?.artistReleaseSections(artistID: artistID)
        ) ?? .empty
    }

    func tracks(tagID: UUID) async -> [LibraryTrackProjection] {
        await (try? repository?.tracks(tagID: tagID).items) ?? []
    }

    func allTrackIDs() async -> [UUID] {
        await (try? repository?.allTrackIDs()) ?? tracks.map(\.id)
    }
}
