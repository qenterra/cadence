import CoreGraphics
import Foundation

typealias LibraryArtworkSetOperation = @Sendable (
    _ service: ManagedArtworkService,
    _ request: ManagedArtworkEditRequest
) async throws -> ManagedArtworkMutationResult

typealias LibraryArtworkPublicationLoader = @Sendable (
    _ repository: LibraryRepository,
    _ effects: [ManagedArtworkPublicationEffect]
) async throws -> LibraryArtworkPublicationPayload

extension LibraryStore {
    @discardableResult
    func setArtwork(
        _ request: ManagedArtworkEditRequest,
        location: ManagedLibraryLocation?,
        operation: LibraryArtworkSetOperation? = nil,
        publicationLoader: LibraryArtworkPublicationLoader? = nil
    ) async throws -> ManagedArtworkMutationResult {
        let context = captureLibraryContext()
        guard let artworkService, location != nil else {
            throw ManagedArtworkEditError.unavailableLibrary
        }
        _ = try requireRepository()
        let result: ManagedArtworkMutationResult
        do {
            result = if let operation {
                try await operation(artworkService, request)
            } else {
                try await artworkService.setArtwork(request)
            }
        } catch {
            let resolvedError = await artworkMutationError(
                preserving: error,
                context: context,
                service: artworkService
            )
            throw resolvedError
        }
        guard ownsArtworkOperation(context, service: artworkService) else {
            return result.suppressingPublicationEffects()
        }
        await publishArtworkEffects(
            result.effects,
            context: context,
            service: artworkService,
            loader: publicationLoader
        )
        guard ownsArtworkOperation(context, service: artworkService) else {
            return result.suppressingPublicationEffects()
        }
        return result
    }

    @discardableResult
    func removeArtwork(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID,
        location: ManagedLibraryLocation?
    ) async throws -> ManagedArtworkMutationResult {
        let context = captureLibraryContext()
        guard let artworkService, location != nil else {
            throw ManagedArtworkEditError.unavailableLibrary
        }
        _ = try requireRepository()
        let result: ManagedArtworkMutationResult
        do {
            result = try await artworkService.removeArtwork(
                ownerKind: ownerKind,
                ownerID: ownerID
            )
        } catch {
            let resolvedError = await artworkMutationError(
                preserving: error,
                context: context,
                service: artworkService
            )
            throw resolvedError
        }
        guard ownsArtworkOperation(context, service: artworkService) else {
            return result.suppressingPublicationEffects()
        }
        await publishArtworkEffects(
            result.effects,
            context: context,
            service: artworkService
        )
        guard ownsArtworkOperation(context, service: artworkService) else {
            return result.suppressingPublicationEffects()
        }
        return result
    }

    func recoverArtworkEdits() async throws -> ManagedArtworkRecoveryResult {
        let context = captureLibraryContext()
        guard let artworkService else {
            throw ManagedArtworkEditError.unavailableLibrary
        }
        _ = try requireRepository()
        let result: ManagedArtworkRecoveryResult
        do {
            result = try await artworkService.recover()
        } catch {
            guard ownsArtworkOperation(context, service: artworkService) else {
                throw CancellationError()
            }
            throw error
        }
        guard ownsArtworkOperation(context, service: artworkService) else {
            return result.suppressingPublicationEffects()
        }
        await publishArtworkEffects(
            result.effects,
            context: context,
            service: artworkService
        )
        guard ownsArtworkOperation(context, service: artworkService) else {
            return result.suppressingPublicationEffects()
        }
        return result
    }

    private func publishArtworkEffects(
        _ effects: [ManagedArtworkPublicationEffect],
        context: LibraryStoreContext,
        service: ManagedArtworkService,
        loader: LibraryArtworkPublicationLoader? = nil
    ) async {
        guard
            !effects.isEmpty,
            ownsArtworkOperation(context, service: service)
        else {
            return
        }
        let affectedArtworkIDs = Set(
            effects.flatMap { effect in
                [
                    effect.previousArtworkID,
                    effect.newArtworkID,
                ].compactMap(\.self)
            }
        )
        invalidateArtworkLookupState(for: affectedArtworkIDs)
        guard let repository = context.repository else {
            return
        }
        artworkPublicationGeneration &+= 1
        let generation = artworkPublicationGeneration
        let payload: LibraryArtworkPublicationPayload
        do {
            payload = if let loader {
                try await loader(repository, effects)
            } else {
                try await repository.artworkPublicationPayload(for: effects)
            }
        } catch {
            guard
                generation == artworkPublicationGeneration,
                ownsArtworkOperation(context, service: service)
            else {
                return
            }
            recordOperationFailure(.artworkLoad, error: error)
            return
        }
        guard
            generation == artworkPublicationGeneration,
            ownsArtworkOperation(context, service: service)
        else {
            return
        }

        retireArtworkSensitiveProjectionLoads()
        publishArtworkPayload(payload)
        artworkPublication = LibraryArtworkPublication(
            epoch: context.epoch,
            generation: generation,
            effects: effects,
            payload: payload
        )
    }

    private func retireArtworkSensitiveProjectionLoads() {
        initialLibraryLoadGeneration &+= 1
        trackRequestGeneration &+= 1
        browserAlbumGeneration &+= 1
        browserTrackGeneration &+= 1
        selectedPlaylistTracksGeneration &+= 1
        playbackQueueProjectionGeneration &+= 1
        smartCollectionResultGeneration &+= 1
        retireCatalogSearchForArtworkPublication()
        isLoadingNextTracks = false
        isLoadingNextBrowserAlbums = false
        isLoadingNextBrowserTracks = false
        isLoadingPlaybackQueueTracks = false
        isLoadingNextSmartCollectionResult = false
        if availability == .loading {
            availability = .ready
        }
    }

    private func publishArtworkPayload(
        _ payload: LibraryArtworkPublicationPayload
    ) {
        if !payload.tracksByID.isEmpty {
            advanceAllTracksWindowContentVersion()
        }
        for projection in payload.tracksByID.values {
            publishTrackProjection(projection)
        }
        publishTrackArtworkInLyrics(payload.tracksByID)
        publishAlbumArtwork(payload.albumsByID)
        publishArtistArtwork(payload.artistsByID)
        publishPlaylistArtwork(payload.playlistsByID)
    }

    private func publishTrackArtworkInLyrics(
        _ projections: [UUID: LibraryTrackProjection]
    ) {
        guard !projections.isEmpty else {
            return
        }
        catalogSearchResults.lyrics = catalogSearchResults.lyrics.map { result in
            guard let track = projections[result.track.id] else {
                return result
            }
            return LyricsCatalogSearchResult(track: track, match: result.match)
        }
    }

    private func publishAlbumArtwork(
        _ projections: [UUID: LibraryAlbumProjection]
    ) {
        for projection in projections.values {
            albums.replaceArtworkElement(projection)
            favoriteAlbums.replaceArtworkElement(projection)
            browserAlbums.replaceArtworkElement(projection)
            catalogSearchResults.albums.replaceArtworkElement(projection)
        }
    }

    private func publishArtistArtwork(
        _ projections: [UUID: LibraryArtistProjection]
    ) {
        for projection in projections.values {
            artists.replaceArtworkElement(projection)
            favoriteArtists.replaceArtworkElement(projection)
            catalogSearchResults.artists.replaceArtworkElement(projection)
        }
    }

    private func publishPlaylistArtwork(
        _ projections: [UUID: LibraryPlaylistProjection]
    ) {
        for projection in projections.values {
            playlists.replaceArtworkElement(projection)
        }
    }

    private func artworkMutationError(
        preserving error: any Error,
        context: LibraryStoreContext,
        service: ManagedArtworkService
    ) async -> any Error {
        guard ownsArtworkOperation(context, service: service) else {
            return CancellationError()
        }
        guard let failure = error as? any ManagedArtworkRecoveryCarryingError
        else {
            return error
        }
        await publishArtworkEffects(
            failure.recovery.effects,
            context: context,
            service: service
        )
        guard ownsArtworkOperation(context, service: service) else {
            return CancellationError()
        }
        return failure.underlyingError
    }

    private func invalidateArtworkLookupState(for ids: Set<UUID>) {
        for id in ids {
            artworkLookupGenerations[id, default: 0] &+= 1
            artworkMetadataResults.invalidate(id: id)
            artworkMetadataLoads.removeValue(forKey: id)?.cancel()
            let dataKeys = artworkDataLoads.keys.filter { $0.id == id }
            for key in dataKeys {
                artworkDataLoads.removeValue(forKey: key)?.cancel()
            }
            artworkAssetCache.invalidate(id: id)
        }
    }

    private func ownsArtworkOperation(
        _ context: LibraryStoreContext,
        service: ManagedArtworkService
    ) -> Bool {
        isCurrentLibraryContext(context) && artworkService === service
    }
}

private extension Array where Element: Identifiable & Equatable, Element.ID == UUID {
    mutating func replaceArtworkElement(_ replacement: Element) {
        guard
            let index = firstIndex(where: { $0.id == replacement.id }),
            self[index] != replacement
        else {
            return
        }
        self[index] = replacement
    }
}

private extension ManagedArtworkMutationResult {
    func suppressingPublicationEffects() -> ManagedArtworkMutationResult {
        ManagedArtworkMutationResult(
            primaryArtworkID: primaryArtworkID,
            effects: []
        )
    }
}

private extension ManagedArtworkRecoveryResult {
    func suppressingPublicationEffects() -> ManagedArtworkRecoveryResult {
        ManagedArtworkRecoveryResult(
            recoveredOperationIDs: recoveredOperationIDs,
            rolledBackOperationIDs: rolledBackOperationIDs,
            effects: []
        )
    }
}
