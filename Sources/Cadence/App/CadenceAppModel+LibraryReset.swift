import Foundation

extension CadenceAppModel {
    func deleteEntireManagedLibrary() async {
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
        librarySession.prepareForLibraryReplacement()

        do {
            let prepared = try await libraryResetter.prepare(
                location: location
            )
            do {
                let activation = try locationController.prepareActivation(
                    parentURL: location.musicDirectory,
                    identity: prepared.identity
                )
                do {
                    try await activateLibrary(at: location)
                    locationController.commit(activation)
                } catch {
                    locationController.cancel(activation)
                    throw error
                }

                await remoteLibraryController?.disconnect()
                resetNavigationAfterLibraryDeletion()
                if await !(libraryResetter.finish(prepared)) {
                    libraryResetNotice = "The library was reset, but the original package "
                        + "could not be moved to Trash. It remains at \(prepared.backupURL.path)."
                }
            } catch {
                try await restoreLibrary(
                    prepared,
                    fallbackError: error
                )
            }
        } catch {
            try? await reopenLibrary(at: location)
            libraryResetNotice = error.localizedDescription
        }

        libraryResetRevision &+= 1
        isResettingLibrary = false
    }

    func dismissLibraryResetNotice() {
        libraryResetNotice = nil
    }
}

private extension CadenceAppModel {
    func activateLibrary(
        at location: ManagedLibraryLocation
    ) async throws {
        let package = ManagedLibraryPackage(location: location)
        let container = try LibraryContainerFactory.persistent(
            package: package
        )
        let repository = LibraryRepository(modelContainer: container)
        await librarySession.activate(repository: repository)
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

    func restoreLibrary(
        _ prepared: PreparedLibraryReset,
        fallbackError: Error
    ) async throws {
        librarySession.prepareForLibraryReplacement()
        do {
            _ = try await libraryResetter.rollback(prepared)
            try await reopenLibrary(at: prepared.location)
            libraryResetNotice = fallbackError.localizedDescription
        } catch {
            librarySession.fail(message: error.localizedDescription)
            libraryResetNotice = error.localizedDescription
            throw error
        }
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
