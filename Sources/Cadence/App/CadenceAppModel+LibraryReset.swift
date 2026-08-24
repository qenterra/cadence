import Foundation

typealias LibraryResetFailureCheckpoint = @MainActor @Sendable () async -> Void
typealias LibraryResetReopenOperation = @MainActor @Sendable (
    _ location: ManagedLibraryLocation
) async throws -> Void
enum LibraryResetCheckpointPhase: Sendable {
    case packagePrepared
    case packageRolledBack
    case locationCommitted
}

typealias LibraryResetCheckpoint = @MainActor @Sendable (
    _ phase: LibraryResetCheckpointPhase
) async -> Void
typealias LibraryResetReplacementActivation = @MainActor @Sendable (
    _ location: ManagedLibraryLocation
) async throws -> Void

extension CadenceAppModel {
    func deleteEntireManagedLibrary(
        checkpoint: LibraryResetCheckpoint? = nil,
        replacementActivation: LibraryResetReplacementActivation? = nil
    ) async {
        guard !isResettingLibrary else {
            return
        }
        guard
            let location = librarySession.location,
            let locationController = librarySession.locationController
        else {
            libraryResetNotice = "The managed library location is unavailable."
            return
        }

        isResettingLibrary = true
        libraryResetNotice = nil
        shutdownPlayback()
        importCoordinator?.cancel()
        clearImportPipeline()

        defer {
            libraryResetRevision &+= 1
            isResettingLibrary = false
        }

        do {
            try await librarySession.performTransition { transition in
                try await self.performLibraryResetLocked(
                    at: location,
                    locationController: locationController,
                    transition: transition,
                    checkpoint: checkpoint,
                    replacementActivation: replacementActivation
                )
            }
        } catch is CancellationError {
            return
        } catch {
            if libraryResetNotice == nil {
                libraryResetNotice = error.localizedDescription
            }
        }
    }

    func dismissLibraryResetNotice() {
        libraryResetNotice = nil
    }

    func handleResetPreparationFailure(
        _ resetError: Error,
        location: ManagedLibraryLocation,
        failureCheckpoint: LibraryResetFailureCheckpoint? = nil,
        reopenOperation: LibraryResetReopenOperation? = nil
    ) async {
        do {
            if let reopenOperation {
                try await reopenOperation(location)
            } else {
                try await reopenLibrary(at: location)
            }
            libraryResetNotice = resetError.localizedDescription
        } catch {
            if let failureCheckpoint {
                await failureCheckpoint()
            }
            libraryResetNotice = error.localizedDescription
        }
    }
}

private extension CadenceAppModel {
    func performLibraryResetLocked(
        at location: ManagedLibraryLocation,
        locationController: LibraryLocationController,
        transition: LibrarySessionTransitionToken,
        checkpoint: LibraryResetCheckpoint?,
        replacementActivation: LibraryResetReplacementActivation?
    ) async throws {
        try await librarySession.prepareForLibraryReplacementLocked(
            transition: transition
        )
        let prepared = try await prepareLibraryResetPackageLocked(
            at: location,
            transition: transition,
            checkpoint: checkpoint
        )
        do {
            try await commitReplacementLibraryLocked(
                prepared: prepared,
                locationController: locationController,
                transition: transition,
                checkpoint: checkpoint,
                replacementActivation: replacementActivation
            )
        } catch {
            try await compensateLibraryResetLocked(
                prepared: prepared,
                location: location,
                transition: transition,
                fallbackError: error,
                checkpoint: checkpoint
            )
            throw error
        }
        if let repository = librarySession.store.repository {
            configureImportPipeline(
                location: location,
                repository: repository
            )
        }
        await checkpoint?(.locationCommitted)
        await finishCommittedLibraryResetLocked(prepared)
    }

    func prepareLibraryResetPackageLocked(
        at location: ManagedLibraryLocation,
        transition: LibrarySessionTransitionToken,
        checkpoint: LibraryResetCheckpoint?
    ) async throws -> PreparedLibraryReset {
        do {
            return try await libraryResetter.prepare(location: location)
        } catch {
            try await compensateLibraryResetLocked(
                prepared: nil,
                location: location,
                transition: transition,
                fallbackError: error,
                checkpoint: checkpoint
            )
            throw error
        }
    }

    func commitReplacementLibraryLocked(
        prepared: PreparedLibraryReset,
        locationController: LibraryLocationController,
        transition: LibrarySessionTransitionToken,
        checkpoint: LibraryResetCheckpoint?,
        replacementActivation: LibraryResetReplacementActivation?
    ) async throws {
        await checkpoint?(.packagePrepared)
        try librarySession.requireCurrentTransition(transition)
        let activation = try locationController
            .prepareReplacementForCurrentLocation(
                parentURL: prepared.location.musicDirectory,
                identity: prepared.identity
            )
        do {
            if let replacementActivation {
                try await replacementActivation(prepared.location)
                try validateReplacementLibraryLocked(
                    transition: transition
                )
            } else {
                try await activateLibraryLocked(
                    at: prepared.location,
                    transition: transition
                )
            }
            try librarySession.requireCurrentTransition(transition)
            try locationController.commit(activation)
        } catch {
            locationController.cancel(activation)
            throw error
        }
    }

    func validateReplacementLibraryLocked(
        transition: LibrarySessionTransitionToken
    ) throws {
        try librarySession.requireCurrentTransition(transition)
        guard
            librarySession.store.repository != nil,
            librarySession.store.availability == .ready
        else {
            throw ManagedLibraryResetError.invalidPackage(
                "The replacement library did not become ready."
            )
        }
    }

    func activateLibraryLocked(
        at location: ManagedLibraryLocation,
        transition: LibrarySessionTransitionToken
    ) async throws {
        let package = ManagedLibraryPackage(location: location)
        let container = try LibraryContainerFactory.persistentLocal(
            package: package
        )
        let repository = LibraryRepository(modelContainer: container)
        try await librarySession.activateLocked(
            repository: repository,
            package: package,
            transition: transition
        )
        guard librarySession.availability == .ready else {
            let message: String = if case let .failed(failure) = librarySession.availability {
                failure.message
            } else {
                "The replacement library did not become ready."
            }
            throw ManagedLibraryResetError.invalidPackage(message)
        }
    }

    func compensateLibraryResetLocked(
        prepared: PreparedLibraryReset?,
        location: ManagedLibraryLocation,
        transition: LibrarySessionTransitionToken,
        fallbackError: Error,
        checkpoint: LibraryResetCheckpoint?
    ) async throws {
        do {
            let published = try await Task { @MainActor in
                try await self.librarySession
                    .detachForResetCompensationLocked(
                        transition: transition
                    )
                if let prepared {
                    _ = try await self.libraryResetter.rollback(prepared)
                    await checkpoint?(.packageRolledBack)
                }
                return try await self.restoreOriginalLibraryLocked(
                    at: location,
                    transition: transition
                )
            }.value
            if published, !(fallbackError is CancellationError) {
                libraryResetNotice = fallbackError.localizedDescription
            }
        } catch {
            libraryResetNotice = error.localizedDescription
            _ = try? librarySession.publishResetCompensationFailureLocked(
                message: error.localizedDescription,
                transition: transition
            )
            throw error
        }
    }

    func restoreOriginalLibraryLocked(
        at location: ManagedLibraryLocation,
        transition: LibrarySessionTransitionToken
    ) async throws -> Bool {
        let package = ManagedLibraryPackage(location: location)
        let container = try LibraryContainerFactory.persistentLocal(
            package: package
        )
        let repository = LibraryRepository(modelContainer: container)
        let published = try await librarySession
            .restoreLibraryForResetCompensationLocked(
                repository: repository,
                package: package,
                transition: transition
            )
        if published {
            configureImportPipeline(
                location: location,
                repository: repository
            )
        }
        return published
    }

    func finishCommittedLibraryResetLocked(
        _ prepared: PreparedLibraryReset
    ) async {
        await Task { @MainActor in
            await self.remoteLibraryController?.disconnect()
            self.resetNavigationAfterLibraryDeletion()
            if await !(self.libraryResetter.finish(prepared)) {
                self.libraryResetNotice = "The library was reset, but the original package "
                    + "could not be moved to Trash. It remains at \(prepared.backupURL.path)."
            }
        }.value
    }

    func activateLibrary(
        at location: ManagedLibraryLocation
    ) async throws {
        let package = ManagedLibraryPackage(location: location)
        let container = try LibraryContainerFactory.persistentLocal(
            package: package
        )
        let repository = LibraryRepository(modelContainer: container)
        try await librarySession.activate(repository: repository)
        guard librarySession.availability == .ready else {
            let message: String = if case let .failed(failure) = librarySession.availability {
                failure.message
            } else {
                "The replacement library did not become ready."
            }
            throw ManagedLibraryResetError.invalidPackage(message)
        }
        configureImportPipeline(
            location: location,
            repository: repository
        )
    }

    func reopenLibrary(
        at location: ManagedLibraryLocation
    ) async throws {
        try await activateLibrary(at: location)
    }

    func clearImportPipeline() {
        importCoordinator = nil
        importDestination = nil
        importRecovery = nil
    }

    func resetNavigationAfterLibraryDeletion() {
        selectedDestination = .home
        selectedProductionArtistID = nil
        selectedProductionAlbumID = nil
        selectedProductionTagID = nil
        selectedProductionTagEditingTrackID = nil
        playbackWorkspace = .hidden
        searchQuery = ""
        librarySession.store.clearCatalogSearch()
    }
}
