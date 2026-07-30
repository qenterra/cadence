import Foundation

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
            librarySession.availability != .preview,
            let importRecovery,
            let importDestination
        else {
            return
        }
        librarySession.beginRecovery()
        do {
            _ = try await importRecovery.recover()
            _ = try await librarySession.store.recoverLyricsEdits()
            if let repository = await importDestination.currentRepository() {
                await librarySession.activate(repository: repository)
            } else {
                librarySession.finishRecoveryWithoutLibrary()
            }
        } catch {
            librarySession.fail(message: error.localizedDescription)
        }
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
            completedCount: candidates.count,
            totalCount: candidates.count,
            currentFilename: candidates.last?.sourceFilename
        )
        importPreviewStage = .review
        importReviewCategory = .ready
        selectedImportCandidateIDs.removeAll()
        importSelectionAnchorID = nil
        selectFirstVisibleImportCandidate()
    }

    private func activateManagedLibraryAfterImport() async {
        guard
            let repository = await importDestination?.currentRepository()
        else {
            return
        }
        await librarySession.activate(repository: repository)
    }
}
