import Foundation

typealias LibraryLyricsSaveOperation = @Sendable (
    _ service: ManagedLyricsService,
    _ document: LyricDocument
) async throws -> ManagedLyricsSaveResult

extension LibraryStore {
    func lyricsDocument(
        trackID: UUID
    ) async throws -> LyricDocument? {
        let context = captureLibraryContext()
        guard let lyricsService else {
            throw ManagedLyricsServiceError.unavailable
        }
        let projectionRepository = repository
        let result: ManagedLyricsLoadResult
        do {
            result = try await lyricsService.loadResult(trackID: trackID)
        } catch {
            guard ownsLyricsOperation(context, service: lyricsService) else {
                throw CancellationError()
            }
            throw error
        }
        guard ownsLyricsOperation(context, service: lyricsService) else {
            return nil
        }
        if result.didRepairMetadata, let projectionRepository {
            await publishTrackProjectionsBestEffort(
                trackIDs: [trackID],
                repository: projectionRepository,
                context: context,
                service: lyricsService
            )
            guard ownsLyricsOperation(context, service: lyricsService) else {
                return nil
            }
        }
        await synchronizeLyricsSearchBestEffort(
            trackIDs: [trackID],
            context: context,
            service: lyricsService
        )
        guard ownsLyricsOperation(context, service: lyricsService) else {
            return nil
        }
        return result.document
    }

    func saveLyrics(
        _ document: LyricDocument,
        operation: LibraryLyricsSaveOperation? = nil
    ) async throws {
        let context = captureLibraryContext()
        guard let lyricsService else {
            throw ManagedLyricsServiceError.unavailable
        }
        let projectionRepository = repository
        let result: ManagedLyricsSaveResult
        do {
            result = if let operation {
                try await operation(lyricsService, document)
            } else {
                try await lyricsService.save(document)
            }
        } catch {
            let resolvedError = await lyricsSaveError(
                preserving: error,
                repository: projectionRepository,
                context: context,
                service: lyricsService
            )
            throw resolvedError
        }
        guard ownsLyricsOperation(context, service: lyricsService) else {
            return
        }
        if let projectionRepository {
            await publishTrackProjectionsBestEffort(
                trackIDs: result.affectedTrackIDs,
                repository: projectionRepository,
                context: context,
                service: lyricsService
            )
            guard ownsLyricsOperation(context, service: lyricsService) else {
                return
            }
        }
        await synchronizeLyricsSearchBestEffort(
            trackIDs: Set(result.affectedTrackIDs),
            context: context,
            service: lyricsService
        )
    }

    func recoverLyricsEdits() async throws -> ManagedLyricsRecoveryResult {
        let context = captureLibraryContext()
        guard let lyricsService else {
            throw ManagedLyricsServiceError.unavailable
        }
        let projectionRepository = repository
        let result: ManagedLyricsRecoveryResult
        do {
            result = try await lyricsService.recover()
        } catch {
            guard ownsLyricsOperation(context, service: lyricsService) else {
                throw CancellationError()
            }
            throw error
        }
        guard ownsLyricsOperation(context, service: lyricsService) else {
            return result
        }
        guard !result.affectedTrackIDs.isEmpty else {
            return result
        }
        if let projectionRepository {
            await publishTrackProjectionsBestEffort(
                trackIDs: result.affectedTrackIDs,
                repository: projectionRepository,
                context: context,
                service: lyricsService
            )
            guard ownsLyricsOperation(context, service: lyricsService) else {
                return result
            }
        }
        await synchronizeLyricsSearchBestEffort(
            trackIDs: Set(result.affectedTrackIDs),
            context: context,
            service: lyricsService
        )
        return result
    }
}

private extension LibraryStore {
    func lyricsSaveError(
        preserving error: any Error,
        repository: LibraryRepository?,
        context: LibraryStoreContext,
        service: ManagedLyricsService
    ) async -> any Error {
        guard ownsLyricsOperation(context, service: service) else {
            return CancellationError()
        }
        guard let failure = error as? any ManagedLyricsRecoveryCarryingError
        else {
            return error
        }
        let trackIDs = failure.recovery.affectedTrackIDs
        if let repository {
            await publishTrackProjectionsBestEffort(
                trackIDs: trackIDs,
                repository: repository,
                context: context,
                service: service
            )
            guard ownsLyricsOperation(context, service: service) else {
                return CancellationError()
            }
        }
        await synchronizeLyricsSearchBestEffort(
            trackIDs: Set(trackIDs),
            context: context,
            service: service
        )
        guard ownsLyricsOperation(context, service: service) else {
            return CancellationError()
        }
        return failure.underlyingError
    }

    func ownsLyricsOperation(
        _ context: LibraryStoreContext,
        service: ManagedLyricsService
    ) -> Bool {
        isCurrentLibraryContext(context) && lyricsService === service
    }

    func publishTrackProjectionsBestEffort(
        trackIDs: [UUID],
        repository: LibraryRepository,
        context: LibraryStoreContext,
        service: ManagedLyricsService
    ) async {
        guard
            !trackIDs.isEmpty,
            ownsLyricsOperation(context, service: service),
            let projections = try? await repository.tracks(
                ids: Set(trackIDs)
            )
        else {
            return
        }
        guard ownsLyricsOperation(context, service: service) else {
            return
        }
        for projection in projections {
            publishTrackProjection(projection)
        }
    }

    func synchronizeLyricsSearchBestEffort(
        trackIDs: Set<UUID>,
        context: LibraryStoreContext,
        service: ManagedLyricsService
    ) async {
        guard
            ownsLyricsOperation(context, service: service),
            let indexer = lyricsSearchIndexer
        else {
            return
        }
        await synchronizeLyricsSearch(
            trackIDs: trackIDs,
            for: context,
            indexer: indexer
        )
    }
}
