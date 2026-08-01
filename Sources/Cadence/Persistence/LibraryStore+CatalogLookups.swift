import Foundation

extension LibraryStore {
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
        await (try? repository?.tracks(artistID: artistID).items) ?? []
    }

    func albums(artistID: UUID) async -> [LibraryAlbumProjection] {
        await (try? repository?.albums(artistID: artistID)) ?? []
    }

    func tracks(tagID: UUID) async -> [LibraryTrackProjection] {
        await (try? repository?.tracks(tagID: tagID).items) ?? []
    }

    func allTrackIDs() async -> [UUID] {
        await (try? repository?.allTrackIDs()) ?? tracks.map(\.id)
    }
}
