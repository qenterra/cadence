import Foundation

struct LibraryCatalogLookupClient: Sendable {
    let artist: @Sendable (UUID) async throws -> LibraryArtistProjection?
    let album: @Sendable (UUID) async throws -> LibraryAlbumProjection?
    let albumTracks: @Sendable (UUID) async throws -> [LibraryTrackProjection]
    let artistTracks: @Sendable (UUID) async throws -> [LibraryTrackProjection]
    let artistAlbums: @Sendable (UUID) async throws -> [LibraryAlbumProjection]
    let artistReleases: @Sendable (UUID) async throws -> ArtistReleaseSections
    let tagTracks: @Sendable (UUID) async throws -> [LibraryTrackProjection]
    let allTrackIDs: @Sendable () async throws -> [UUID]

    init(
        artist: @escaping @Sendable (UUID) async throws -> LibraryArtistProjection?,
        album: @escaping @Sendable (UUID) async throws -> LibraryAlbumProjection?,
        albumTracks: @escaping @Sendable (UUID) async throws -> [LibraryTrackProjection],
        artistTracks: @escaping @Sendable (UUID) async throws -> [LibraryTrackProjection],
        artistAlbums: @escaping @Sendable (UUID) async throws -> [LibraryAlbumProjection],
        artistReleases: @escaping @Sendable (UUID) async throws -> ArtistReleaseSections,
        tagTracks: @escaping @Sendable (UUID) async throws -> [LibraryTrackProjection],
        allTrackIDs: @escaping @Sendable () async throws -> [UUID]
    ) {
        self.artist = artist
        self.album = album
        self.albumTracks = albumTracks
        self.artistTracks = artistTracks
        self.artistAlbums = artistAlbums
        self.artistReleases = artistReleases
        self.tagTracks = tagTracks
        self.allTrackIDs = allTrackIDs
    }

    init(repository: LibraryRepository) {
        artist = { try await repository.artist(id: $0) }
        album = { try await repository.album(id: $0) }
        albumTracks = {
            try await repository.albumTracksInPlaybackOrder(albumID: $0)
        }
        artistTracks = {
            try await Self.collectTracks(repository: repository, scope: .artist($0))
        }
        artistAlbums = { try await repository.albums(artistID: $0) }
        artistReleases = {
            try await repository.artistReleaseSections(artistID: $0)
        }
        tagTracks = {
            try await Self.collectTagTracks(repository: repository, tagID: $0)
        }
        allTrackIDs = { try await repository.allTrackIDs() }
    }

    private static func collectTracks(
        repository: LibraryRepository,
        scope: LibraryTrackScope
    ) async throws -> [LibraryTrackProjection] {
        var tracks: [LibraryTrackProjection] = []
        var cursor: LibraryPageCursor?
        repeat {
            let page = try await repository.tracksPage(
                query: LibraryTrackQuery(scope: scope),
                after: cursor
            )
            tracks.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil
        return deduplicated(tracks)
    }

    private static func collectTagTracks(
        repository: LibraryRepository,
        tagID: UUID
    ) async throws -> [LibraryTrackProjection] {
        var tracks: [LibraryTrackProjection] = []
        var cursor: LibraryPageCursor?
        repeat {
            let page = try await repository.tracks(
                tagID: tagID,
                after: cursor
            )
            tracks.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil
        return deduplicated(tracks)
    }

    private static func deduplicated(
        _ tracks: [LibraryTrackProjection]
    ) -> [LibraryTrackProjection] {
        var seen: Set<UUID> = []
        return tracks.filter { seen.insert($0.id).inserted }
    }
}

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

    func artist(id: UUID) async throws -> LibraryArtistProjection? {
        guard let catalogLookupClient else {
            throw CatalogLookupError.unavailable
        }
        return try await catalogLookupClient.artist(id)
    }

    func album(id: UUID) async throws -> LibraryAlbumProjection? {
        guard let catalogLookupClient else {
            throw CatalogLookupError.unavailable
        }
        return try await catalogLookupClient.album(id)
    }

    func tracks(albumID: UUID) async throws -> [LibraryTrackProjection] {
        guard let catalogLookupClient else {
            throw CatalogLookupError.unavailable
        }
        return try await catalogLookupClient.albumTracks(albumID)
    }

    func tracks(artistID: UUID) async throws -> [LibraryTrackProjection] {
        guard let catalogLookupClient else {
            throw CatalogLookupError.unavailable
        }
        return try await catalogLookupClient.artistTracks(artistID)
    }

    func artistReleaseSections(
        artistID: UUID
    ) async throws -> ArtistReleaseSections {
        guard let catalogLookupClient else {
            throw CatalogLookupError.unavailable
        }
        return try await catalogLookupClient.artistReleases(artistID)
    }

    func tracks(tagID: UUID) async throws -> [LibraryTrackProjection] {
        guard let catalogLookupClient else {
            throw CatalogLookupError.unavailable
        }
        return try await catalogLookupClient.tagTracks(tagID)
    }

    func allTrackIDs() async throws -> [UUID] {
        guard let catalogLookupClient else {
            throw CatalogLookupError.unavailable
        }
        return try await catalogLookupClient.allTrackIDs()
    }
}

enum CatalogLookupError: Error, LocalizedError, Sendable {
    case unavailable

    var errorDescription: String? {
        "The library catalog is unavailable."
    }
}
