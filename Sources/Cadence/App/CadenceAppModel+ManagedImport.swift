import Foundation

typealias ManagedArtworkRecoveryOperation = @MainActor @Sendable (
    _ store: LibraryStore
) async throws -> ManagedArtworkRecoveryResult

enum ManagedRecoveryCheckpointPhase: Equatable, Sendable {
    case beforeAttachment
    case beforePublication
}

typealias ManagedRecoveryCheckpoint = @MainActor @Sendable (
    ManagedRecoveryCheckpointPhase
) async -> Void

typealias ManagedImportActivationFailureCheckpoint = @MainActor @Sendable () async -> Void

extension CadenceAppModel {
    func applyImportCoordinatorState(
        _ state: ImportCoordinatorState
    ) {
        switch state {
        case .empty:
            resetProductionImportState()
        case let .scanning(progress):
            importPreviewStage = .scanning
            importScanProgress = progress
        case let .review(candidates):
            applyReviewedCandidates(candidates)
        case let .importing(progress):
            managedImportProgress = progress
            importPreviewStage = .importing
            selectedImportCandidateIDs.removeAll()
            importSelectionAnchorID = nil
        case let .complete(completion):
            managedImportProgress = nil
            managedImportCompletion = completion
            importPreviewStage = .complete
            Task {
                await activateManagedLibraryAfterImport()
            }
        case let .importFailed(message):
            importOperationError = message
            managedImportProgress = nil
            importPreviewStage = .review
        case let .failed(message):
            importScanError = message
            importPreviewStage = .empty
            importScanProgress = .empty
        }
    }

    func recoverManagedLibraryIfNeeded() async {
        guard
            librarySession.availability == .recovering
        else {
            return
        }
        await openAndRecoverManagedLibrary()
    }

    func retryManagedLibrary() async {
        guard
            case let .failed(failure) = librarySession.availability,
            failure.kind != .locationUnavailable,
            failure.kind != .staleBookmark,
            failure.kind != .identityMismatch
        else {
            return
        }
        await openAndRecoverManagedLibrary()
    }

    private func openAndRecoverManagedLibrary() async {
        guard let importRecovery, let importDestination else {
            return
        }
        do {
            try await librarySession.performTransition { transition in
                do {
                    try await self.recoverManagedLibrary(
                        importRecovery: importRecovery,
                        importDestination: importDestination,
                        transition: transition
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try self.librarySession.publishFailure(
                        kind: .recoveryFailed,
                        message: error.localizedDescription,
                        transition: transition
                    )
                    throw error
                }
            }
        } catch {
            return
        }
    }

    private func recoverManagedLibrary(
        importRecovery: ManagedLibraryImportRecovery,
        importDestination: ManagedLibraryImportDestination,
        transition: LibrarySessionTransitionToken
    ) async throws {
        let repository = try await prepareManagedRecoveryRepository(
            importDestination: importDestination,
            transition: transition
        )
        let artworkRecovery = try await recoverManagedLibraryState(
            importRecovery: importRecovery,
            repository: repository,
            transition: transition
        )
        try await publishManagedRecovery(
            artworkRecovery,
            transition: transition
        )
    }

    private func prepareManagedRecoveryRepository(
        importDestination: ManagedLibraryImportDestination,
        transition: LibrarySessionTransitionToken
    ) async throws -> LibraryRepository {
        if let location = librarySession.location {
            try await LibraryRelocationRecovery().recover(
                activeLocation: location
            )
        }
        try librarySession.requireTransitionOwnership(transition)
        let repository = try await importDestination.prepareRepository()
        try librarySession.requireTransitionOwnership(transition)
        if let location = librarySession.location {
            _ = try await repository.reconcileTrash(location: location)
        }
        try librarySession.requireTransitionOwnership(transition)
        await managedRecoveryCheckpoint(.beforeAttachment)
        try librarySession.requireTransitionOwnership(transition)
        return repository
    }

    private func recoverManagedLibraryState(
        importRecovery: ManagedLibraryImportRecovery,
        repository: LibraryRepository,
        transition: LibrarySessionTransitionToken
    ) async throws -> ManagedArtworkRecoveryResult {
        try await librarySession.store.attach(
            repository: repository,
            package: librarySession.location.map(ManagedLibraryPackage.init)
        )
        try librarySession.requireTransitionOwnership(transition)
        _ = try await importRecovery.recover()
        try librarySession.requireTransitionOwnership(transition)
        _ = try await librarySession.store.recoverLyricsEdits()
        try librarySession.requireTransitionOwnership(transition)
        let artworkRecovery = if let managedArtworkRecoveryOperation {
            try await managedArtworkRecoveryOperation(librarySession.store)
        } else {
            try await librarySession.store.recoverArtworkEdits()
        }
        try librarySession.requireTransitionOwnership(transition)
        await managedRecoveryCheckpoint(.beforePublication)
        try librarySession.requireTransitionOwnership(transition)
        return artworkRecovery
    }

    private func publishManagedRecovery(
        _ artworkRecovery: ManagedArtworkRecoveryResult,
        transition: LibrarySessionTransitionToken
    ) async throws {
        try await librarySession.finishActivationLocked(
            transition: transition
        )
        try librarySession.requireTransitionOwnership(transition)
        applyManagedArtworkPublication(artworkRecovery.effects)
        try librarySession.requireTransitionOwnership(transition)
    }

    func startImportScan(
        source: ImportSource
    ) {
        guard !source.urls.isEmpty, let importCoordinator else {
            return
        }
        importScanError = nil
        importCandidates = []
        includedImportCandidateIDs.removeAll()
        selectedImportCandidateIDs.removeAll()
        importSelectionAnchorID = nil
        importScanProgress = .empty
        importCoordinator.start(source: source)
    }

    private func resetProductionImportState() {
        importPreviewStage = .empty
        importScanProgress = .empty
        importCandidates = []
        includedImportCandidateIDs.removeAll()
        selectedImportCandidateIDs.removeAll()
        importSelectionAnchorID = nil
    }

    private func applyReviewedCandidates(
        _ candidates: [ImportInspectionCandidate]
    ) {
        importCandidates = candidates.map(\.preview)
        includedImportCandidateIDs = Set(
            importCandidates
                .filter(\.isIncludedByDefault)
                .map(\.id)
        )
        importScanProgress = ImportInspectionProgress(
            phase: .scanning,
            completedCount: candidates.count,
            totalCount: candidates.count
        )
        importPreviewStage = .review
        importReviewCategory = .ready
        selectedImportCandidateIDs.removeAll()
        importSelectionAnchorID = nil
        selectFirstVisibleImportCandidate()
    }

    func activateManagedLibraryAfterImport(
        failureCheckpoint: ManagedImportActivationFailureCheckpoint? = nil
    ) async {
        guard
            let repository = await importDestination?.currentRepository()
        else {
            return
        }
        do {
            try await librarySession.activate(repository: repository)
        } catch is CancellationError {
            return
        } catch {
            if let failureCheckpoint {
                await failureCheckpoint()
            }
        }
    }
}
