import AppKit
import Foundation

extension CadenceAppModel {
    var isMovingLibrary: Bool {
        libraryRelocationState.isMoving
    }

    var libraryRelocationProgress: LibraryRelocationProgress? {
        libraryRelocationState.progress
    }

    var libraryRelocationError: String? {
        libraryRelocationState.error
    }

    var pendingLibraryConflictParent: URL? {
        libraryRelocationState.pendingConflictParent
    }

    func chooseLibraryLocation() {
        let panel = NSOpenPanel()
        panel.title = librarySession.location.map { _ in
            "Move Cadence Library"
        } ?? "Choose Library Location"
        panel.message = "Choose a folder for Cadence.library. Local disks, external drives, "
            + "iCloud Drive, and File Provider folders are supported."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parentURL = panel.url else {
            return
        }
        Task {
            await moveLibrary(to: parentURL)
        }
    }

    func locateUnavailableLibrary() {
        guard let controller = librarySession.locationController else {
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Locate Cadence Library"
        panel.message = "Choose the folder that contains your existing Cadence.library package."
        panel.prompt = "Reconnect"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else {
            return
        }
        Task {
            do {
                let activation = try controller.prepareReconnect(
                    parentURL: parent
                )
                let location = ManagedLibraryLocation(musicDirectory: parent)
                let package = ManagedLibraryPackage(location: location)
                let container = try LibraryContainerFactory.persistent(
                    package: package
                )
                let repository = LibraryRepository(modelContainer: container)
                do {
                    try await librarySession.switchLocation(
                        to: location,
                        repository: repository
                    )
                    try controller.commit(activation)
                } catch {
                    controller.cancel(activation)
                    throw error
                }
                reconfigureImportPipeline(
                    location: location,
                    repository: repository
                )
            } catch {
                libraryRelocationState.error = error.localizedDescription
            }
        }
    }

    func moveLibrary(
        to destinationParent: URL
    ) async {
        guard
            !libraryRelocationState.isMoving,
            let source = librarySession.location,
            let controller = librarySession.locationController
        else {
            libraryRelocationState.error = "The current library location cannot be changed in this session."
            return
        }
        libraryRelocationState = LibraryRelocationWorkspaceState(
            progress: .init(
                phase: .preflight,
                completedCount: 0,
                totalCount: 0
            ),
            error: nil,
            pendingConflictParent: nil,
            isMoving: true
        )
        shutdownPlayback()

        do {
            if !FileManager.default.fileExists(atPath: source.packageURL.path) {
                try await activateEmptyLibrary(
                    at: destinationParent,
                    controller: controller
                )
            } else {
                try await relocateExistingLibrary(
                    from: source,
                    to: destinationParent,
                    controller: controller
                )
            }
        } catch let error as LibraryRelocationError {
            if case let .destinationConflict(url) = error {
                libraryRelocationState.pendingConflictParent = url.deletingLastPathComponent()
            } else {
                libraryRelocationState.error = error.localizedDescription
            }
        } catch {
            libraryRelocationState.error = error.localizedDescription
        }
        libraryRelocationState.isMoving = false
        if libraryRelocationState.error == nil,
           libraryRelocationState.pendingConflictParent == nil {
            libraryRelocationState.progress = nil
        }
    }

    func openConflictingLibrary() async {
        guard
            let parent = libraryRelocationState.pendingConflictParent,
            let controller = librarySession.locationController
        else {
            return
        }
        do {
            let location = ManagedLibraryLocation(musicDirectory: parent)
            let package = ManagedLibraryPackage(location: location)
            let identity = try package.readIdentity()
            let container = try LibraryContainerFactory.persistent(package: package)
            let repository = LibraryRepository(modelContainer: container)
            let activation = try controller.prepareActivation(
                parentURL: parent,
                identity: identity
            )
            shutdownPlayback()
            do {
                try await librarySession.switchLocation(
                    to: location,
                    repository: repository
                )
                try controller.commit(activation)
            } catch {
                controller.cancel(activation)
                throw error
            }
            reconfigureImportPipeline(
                location: location,
                repository: repository
            )
            libraryRelocationState = LibraryRelocationWorkspaceState()
        } catch {
            libraryRelocationState.error = error.localizedDescription
            libraryRelocationState.pendingConflictParent = nil
        }
    }

    func chooseAnotherLibraryLocation() {
        libraryRelocationState.pendingConflictParent = nil
        chooseLibraryLocation()
    }

    func dismissLibraryRelocationError() {
        libraryRelocationState.error = nil
        if !libraryRelocationState.isMoving {
            libraryRelocationState.progress = nil
        }
    }

    func configureImportPipeline(
        location: ManagedLibraryLocation,
        repository: LibraryRepository
    ) {
        reconfigureImportPipeline(
            location: location,
            repository: repository
        )
    }
}

private extension CadenceAppModel {
    func relocateExistingLibrary(
        from source: ManagedLibraryLocation,
        to destinationParent: URL,
        controller: LibraryLocationController
    ) async throws {
        let prepared = try await libraryRelocator.prepare(
            source: source,
            destinationParent: destinationParent,
            progress: updateLibraryRelocationProgress
        )
        let activation = try controller.prepareActivation(
            parentURL: destinationParent,
            identity: prepared.manifest.libraryIdentity
        )
        do {
            try await librarySession.switchLocation(
                to: prepared.destination,
                repository: prepared.repository
            )
            try controller.commit(activation)
        } catch {
            controller.cancel(activation)
            throw error
        }
        reconfigureImportPipeline(
            location: prepared.destination,
            repository: prepared.repository
        )
        try await libraryRelocator.finishSwitch(
            prepared,
            progress: updateLibraryRelocationProgress
        )
    }

    var updateLibraryRelocationProgress: @Sendable (LibraryRelocationProgress) async -> Void {
        { [weak self] progress in
            await MainActor.run {
                self?.libraryRelocationState.progress = progress
            }
        }
    }

    func activateEmptyLibrary(
        at destinationParent: URL,
        controller: LibraryLocationController
    ) async throws {
        let location = ManagedLibraryLocation(
            musicDirectory: destinationParent
        )
        let package = ManagedLibraryPackage(location: location)
        guard !FileManager.default.fileExists(atPath: package.packageURL.path) else {
            throw LibraryRelocationError.destinationConflict(package.packageURL)
        }
        try package.bootstrapForConfirmedImport()
        let identity = LibraryIdentity()
        try package.writeIdentity(identity)
        let container = try LibraryContainerFactory.persistent(package: package)
        let repository = LibraryRepository(modelContainer: container)
        let activation = try controller.prepareActivation(
            parentURL: destinationParent,
            identity: identity
        )
        do {
            try await librarySession.switchLocation(
                to: location,
                repository: repository
            )
            try controller.commit(activation)
        } catch {
            controller.cancel(activation)
            throw error
        }
        reconfigureImportPipeline(
            location: location,
            repository: repository
        )
    }

    func reconfigureImportPipeline(
        location: ManagedLibraryLocation,
        repository: LibraryRepository
    ) {
        let destination = ManagedLibraryImportDestination(
            package: ManagedLibraryPackage(location: location),
            repository: repository
        )
        let duplicateLookup = ImportDuplicateLookup { probes in
            try await destination.duplicateEvidence(probes: probes)
        }
        let coordinator = ImportCoordinator(
            service: ImportInspectionService(
                duplicateLookup: duplicateLookup
            ),
            importer: ManagedLibraryImporter(destination: destination)
        )
        coordinator.onStateChange = { [weak self] state in
            self?.applyImportCoordinatorState(state)
        }
        importDestination = destination
        importRecovery = ManagedLibraryImportRecovery(destination: destination)
        importCoordinator = coordinator
    }
}
