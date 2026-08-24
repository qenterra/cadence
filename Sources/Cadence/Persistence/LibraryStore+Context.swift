import Foundation

extension LibraryStore {
    var canLoadMoreTracks: Bool {
        trackCursor != nil
    }

    var tracksVersion: TrackTableContentVersion {
        tracksContentClock.version
    }

    var favoriteTracksVersion: TrackTableContentVersion {
        favoriteTracksContentClock.version
    }

    var browserTracksVersion: TrackTableContentVersion {
        browserTracksContentClock.version
    }

    var selectedPlaylistTracksVersion: TrackTableContentVersion {
        selectedPlaylistTracksContentClock.version
    }

    func ownsSelectedPlaylistTracks(for playlistID: UUID) -> Bool {
        selectedPlaylistID == playlistID
            && selectedPlaylistTracksOwnerID == playlistID
    }

    func selectedPlaylistTrackSource(
        for playlistID: UUID
    ) -> ProductionTrackTableSource? {
        guard ownsSelectedPlaylistTracks(for: playlistID) else {
            return nil
        }
        return ProductionTrackTableSource(
            tracks: selectedPlaylistTracks,
            contentVersion: selectedPlaylistTracksVersion
        )
    }

    var catalogSearchTracksVersion: TrackTableContentVersion {
        catalogSearchTracksContentClock.version
    }

    /// Repository-backed features use this boundary instead of interpreting
    /// missing production dependencies as a successful empty result.
    func requireRepository() throws -> LibraryRepository {
        guard
            attachmentPhase == .active,
            mode == .production,
            let repository
        else {
            throw LibraryStoreAccessError.repositoryUnavailable
        }
        return repository
    }

    func captureLibraryContext() -> LibraryStoreContext {
        LibraryStoreContext(
            epoch: libraryEpoch,
            repository: repository
        )
    }

    func isCurrentLibraryContext(_ context: LibraryStoreContext) -> Bool {
        guard
            attachmentPhase == .active,
            libraryEpoch == context.epoch
        else {
            return false
        }
        switch (repository, context.repository) {
        case (nil, nil):
            return true
        case let (current?, captured?):
            return current === captured
        default:
            return false
        }
    }

    var canLoadMoreArtists: Bool {
        artistCursor != nil
    }

    var canLoadMoreAlbums: Bool {
        albumCursor != nil
    }

    var canLoadMoreTags: Bool {
        tagCursor != nil
    }
}
