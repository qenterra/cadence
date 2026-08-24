import Foundation

typealias LibraryTrackFavoriteOperation = @Sendable (
    _ repository: LibraryRepository,
    _ id: UUID,
    _ isFavorite: Bool
) async throws -> LibraryTrackProjection

typealias LibraryFavoriteAlbumsPageLoader = @Sendable (
    _ repository: LibraryRepository
) async throws -> LibraryPage<LibraryAlbumProjection>

typealias LibraryFavoriteArtistsPageLoader = @Sendable (
    _ repository: LibraryRepository
) async throws -> LibraryPage<LibraryArtistProjection>

extension LibraryStore {
    func setTrackFavorite(
        id: UUID,
        isFavorite: Bool,
        operation: LibraryTrackFavoriteOperation? = nil
    ) async throws -> LibraryTrackProjection {
        let context = captureLibraryContext()
        let repository = try requireRepository()
        let projection: LibraryTrackProjection
        do {
            projection = if let operation {
                try await operation(repository, id, isFavorite)
            } else {
                try await repository.setTrackFavorite(
                    id: id,
                    isFavorite: isFavorite
                )
            }
        } catch {
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            throw error
        }
        guard isCurrentLibraryContext(context) else {
            return projection
        }
        publishTrackProjection(
            projection,
            updatesResidentFavorite: false
        )
        await synchronizeFavoriteTrackMutation(
            projection,
            repository: repository,
            context: context
        )
        return projection
    }

    func setAlbumFavorite(
        id: UUID,
        isFavorite: Bool,
        firstPageLoader: LibraryFavoriteAlbumsPageLoader = {
            try $0.favoriteAlbumsPage()
        }
    ) async throws -> LibraryAlbumProjection {
        let context = captureLibraryContext()
        let repository = try requireRepository()
        let projection: LibraryAlbumProjection
        do {
            projection = try await repository.setAlbumFavorite(
                id: id,
                isFavorite: isFavorite
            )
        } catch {
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            throw error
        }
        guard isCurrentLibraryContext(context) else {
            return projection
        }
        publishFavoriteAlbumProjectionInBaseSources(projection)
        await synchronizeFavoriteAlbumMutation(
            projection,
            repository: repository,
            context: context,
            firstPageLoader: firstPageLoader
        )
        return projection
    }

    func setArtistFavorite(
        id: UUID,
        isFavorite: Bool,
        firstPageLoader: LibraryFavoriteArtistsPageLoader = {
            try $0.favoriteArtistsPage()
        }
    ) async throws -> LibraryArtistProjection {
        let context = captureLibraryContext()
        let repository = try requireRepository()
        let projection: LibraryArtistProjection
        do {
            projection = try await repository.setArtistFavorite(
                id: id,
                isFavorite: isFavorite
            )
        } catch {
            guard isCurrentLibraryContext(context) else {
                throw CancellationError()
            }
            throw error
        }
        guard isCurrentLibraryContext(context) else {
            return projection
        }
        publishFavoriteArtistProjectionInBaseSources(projection)
        await synchronizeFavoriteArtistMutation(
            projection,
            repository: repository,
            context: context,
            firstPageLoader: firstPageLoader
        )
        return projection
    }

    func isTrackFavorite(_ id: UUID) -> Bool {
        favoriteTrackIDs.contains(id)
    }
}

extension LibraryStore {
    func publishTrackProjection(_ projection: LibraryTrackProjection) {
        publishTrackProjection(
            projection,
            updatesResidentFavorite: true
        )
    }
}

private extension LibraryStore {
    func publishTrackProjection(
        _ projection: LibraryTrackProjection,
        updatesResidentFavorite: Bool
    ) {
        publishTrackProjectionInResidentSources(projection)
        publishTrackProjectionInPlaybackQueue(projection)
        publishTrackProjectionInSmartCollections(projection)
        if updatesResidentFavorite {
            publishTrackProjectionInFavorites(projection)
        }
    }

    func publishTrackProjectionInResidentSources(
        _ projection: LibraryTrackProjection
    ) {
        if let window = allTracksWindow,
           window.contentVersion == allTracksWindowContentVersion,
           let index = window.index(ofTrackID: projection.id),
           window.track(at: index) != projection {
            window.replace(projection)
        }
        if let window = favoriteTracksWindow,
           let index = window.index(ofTrackID: projection.id),
           window.track(at: index) != projection {
            window.replace(projection)
        }
        if tracks.replaceElement(id: projection.id, with: projection) {
            tracksContentClock.advance()
        }
        if browserTracks.replaceElement(id: projection.id, with: projection) {
            browserTracksContentClock.advance()
        }
        if selectedPlaylistTracks.replaceElement(
            id: projection.id,
            with: projection
        ) {
            selectedPlaylistTracksContentClock.advance()
        }
        if catalogSearchResults.tracks.replaceElement(
            id: projection.id,
            with: projection
        ) {
            catalogSearchTracksContentClock.advance()
        }
        recentlyPlayedTracks.replaceElement(id: projection.id, with: projection)
    }

    func publishTrackProjectionInPlaybackQueue(
        _ projection: LibraryTrackProjection
    ) {
        let updatedPlaybackQueueTracks = playbackQueueTracks.map { item in
            guard item.id == projection.id else {
                return item
            }
            return PlaybackQueueTrackProjection(
                id: projection.id,
                state: .available(projection)
            )
        }
        if updatedPlaybackQueueTracks != playbackQueueTracks {
            playbackQueueTracks = updatedPlaybackQueueTracks
        }
    }

    func publishTrackProjectionInSmartCollections(
        _ projection: LibraryTrackProjection
    ) {
        for key in smartCollectionResults.keys {
            guard var result = smartCollectionResults[key] else {
                continue
            }
            if result.tracks.replaceElement(
                id: projection.id,
                with: projection
            ) {
                result.contentVersion = result.contentVersion.advanced()
                smartCollectionResults[key] = result
            }
        }
    }

    func publishTrackProjectionInFavorites(
        _ projection: LibraryTrackProjection
    ) {
        if favoriteTracks.replaceElement(
            id: projection.id,
            with: projection
        ) {
            favoriteTracksContentClock.advance()
        }
    }

    func synchronizeFavoriteTrackMutation(
        _ projection: LibraryTrackProjection,
        repository: LibraryRepository,
        context: LibraryStoreContext
    ) async {
        guard isCurrentLibraryContext(context) else {
            return
        }
        let membershipChanged = favoriteTrackIDs.contains(projection.id)
            != projection.isFavorite
        guard membershipChanged else {
            if favoriteTracks.replaceElement(
                id: projection.id,
                with: projection
            ) {
                favoriteTracksContentClock.advance()
            }
            return
        }

        if projection.isFavorite {
            favoriteTrackIDs.insert(projection.id)
        } else {
            favoriteTrackIDs.remove(projection.id)
        }

        guard favoriteTrackCursor != nil else {
            updateCompleteFavoriteTrackSnapshot(with: projection)
            return
        }

        do {
            let page = try await repository.favoriteTracksPage()
            guard isCurrentLibraryContext(context) else {
                return
            }
            replaceFavoriteTracksContent(with: page.items)
            favoriteTrackCursor = page.nextCursor
        } catch {
            guard isCurrentLibraryContext(context) else {
                return
            }
            recordOperationFailure(.favoriteCatalog, error: error)
        }
    }

    func updateCompleteFavoriteTrackSnapshot(
        with projection: LibraryTrackProjection
    ) {
        if projection.isFavorite {
            if favoriteTracks.upsert(
                projection,
                sortedBy: {
                    $0.title.localizedStandardCompare($1.title)
                        == .orderedAscending
                }
            ) {
                favoriteTracksContentClock.advance()
            }
        } else {
            let previousCount = favoriteTracks.count
            favoriteTracks.removeAll { $0.id == projection.id }
            if favoriteTracks.count != previousCount {
                favoriteTracksContentClock.advance()
            }
        }
    }
}

private extension Array where Element: Identifiable & Equatable, Element.ID == UUID {
    @discardableResult
    mutating func replaceElement(id: UUID, with replacement: Element) -> Bool {
        guard let index = firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard self[index] != replacement else {
            return false
        }
        self[index] = replacement
        return true
    }

    @discardableResult
    mutating func upsert(
        _ element: Element,
        sortedBy areInIncreasingOrder: (Element, Element) -> Bool
    ) -> Bool {
        let before = self
        if let index = firstIndex(where: { $0.id == element.id }) {
            self[index] = element
        } else {
            append(element)
        }
        sort(by: areInIncreasingOrder)
        return self != before
    }
}
