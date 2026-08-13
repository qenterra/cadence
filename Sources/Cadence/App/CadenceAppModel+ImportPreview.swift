import AppKit
import Foundation

extension CadenceAppModel {
    var isImportPreviewMode: Bool {
        runtimeMode == .preview
    }

    var visibleImportCandidates: [ImportCandidatePreview] {
        importCandidates.filter {
            $0.classification.reviewCategory == importReviewCategory
        }
    }

    var importPreviewSummary: ImportPreviewSummary {
        if let completion = managedImportCompletion {
            return ImportPreviewSummary(
                importedTrackCount: completion.importedTrackIDs.count,
                linkedLyricsCount: completion.lyricsLinked,
                exactDuplicateCount: completion.exactDuplicatesSkipped,
                issueCount: completion.filesNotImported,
                importedSizeInBytes: completion.importedByteCount
            )
        }
        let includedCandidates = importCandidates.filter {
            includedImportCandidateIDs.contains($0.id)
        }

        return ImportPreviewSummary(
            importedTrackCount: includedCandidates.count,
            linkedLyricsCount: includedCandidates.count {
                $0.lyricStatus == .linked
            },
            exactDuplicateCount: importCandidates.count {
                $0.classification == .exactDuplicate
            },
            issueCount: importCandidates.count {
                $0.classification.reviewCategory == .issues
            },
            importedSizeInBytes: includedCandidates.reduce(0) {
                $0 + $1.sizeInBytes
            }
        )
    }

    var canBeginImportPreview: Bool {
        !includedImportCandidateIDs.isEmpty
            && importPreviewStage == .review
    }

    var importSelectedSizeText: String {
        importPreviewSummary.importedSizeText
    }

    var importSelectedCount: Int {
        includedImportCandidateIDs.count
    }

    func importCandidateCount(
        in category: ImportReviewCategory
    ) -> Int {
        importCandidates.count {
            $0.classification.reviewCategory == category
        }
    }

    func isImportCandidateIncluded(
        _ candidateID: ImportCandidatePreview.ID
    ) -> Bool {
        includedImportCandidateIDs.contains(candidateID)
    }

    func isImportCandidateSelected(
        _ candidateID: ImportCandidatePreview.ID
    ) -> Bool {
        selectedImportCandidateIDs.contains(candidateID)
    }

    func resetImportPreviewCandidates() {
        importCandidates = initialImportCandidates
        includedImportCandidateIDs = Set(
            importCandidates
                .filter(\.isIncludedByDefault)
                .map(\.id)
        )
        selectedImportCandidateIDs.removeAll()
        importSelectionAnchorID = nil
        importReviewCategory = .ready
        managedImportProgress = nil
        managedImportCompletion = nil
    }

    func startImportPreview() {
        isImportPreviewAutoAdvanceEnabled = true
        resetImportPreviewCandidates()
        importPreviewStage = .scanning
    }

    func chooseImportFolder() {
        guard !isImportPreviewMode else {
            startImportPreview()
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose Music Folder"
        panel.prompt = "Review Music"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        startImportScan(source: ImportSource(urls: [url]))
    }

    func cancelImportPreviewScan() {
        guard importPreviewStage == .scanning else {
            return
        }
        if let importCoordinator {
            importCoordinator.cancel()
            return
        }
        importPreviewStage = .empty
        selectedImportCandidateIDs.removeAll()
        importSelectionAnchorID = nil
    }

    func cancelManagedImport() {
        guard importPreviewStage == .importing else {
            return
        }
        importCoordinator?.cancel()
    }

    func completeImportPreviewScan() {
        guard importPreviewStage == .scanning else {
            return
        }
        importPreviewStage = .review
        selectFirstVisibleImportCandidate()
    }

    func selectImportReviewCategory(
        _ category: ImportReviewCategory
    ) {
        guard importReviewCategory != category else {
            return
        }
        importReviewCategory = category
        selectedImportCandidateIDs.removeAll()
        importSelectionAnchorID = nil
        selectFirstVisibleImportCandidate()
    }

    func updateImportCandidateSelection(
        _ intent: ImportCandidateSelectionIntent,
        candidateID: ImportCandidatePreview.ID
    ) {
        let canonicalOrder = visibleImportCandidates.map(\.id)
        guard canonicalOrder.contains(candidateID) else {
            return
        }

        switch intent {
        case .replace:
            selectedImportCandidateIDs = [candidateID]
            importSelectionAnchorID = candidateID
        case .toggle:
            toggleImportCandidateSelection(
                candidateID,
                canonicalOrder: canonicalOrder
            )
        case .range:
            selectImportCandidateRange(
                through: candidateID,
                canonicalOrder: canonicalOrder
            )
        }
    }

    func selectAllImportCandidates() {
        let eligibleIDs = visibleImportCandidates
            .filter(\.isEligible)
            .map(\.id)
        selectedImportCandidateIDs = Set(eligibleIDs)
        importSelectionAnchorID = eligibleIDs.first
    }

    func toggleImportCandidateInclusion(
        _ candidateID: ImportCandidatePreview.ID
    ) {
        guard importCandidates.contains(where: {
            $0.id == candidateID && $0.isEligible
        }) else {
            return
        }

        if includedImportCandidateIDs.contains(candidateID) {
            includedImportCandidateIDs.remove(candidateID)
        } else {
            includedImportCandidateIDs.insert(candidateID)
        }
    }

    func toggleSelectedImportCandidateInclusion() {
        let eligibleSelection = importCandidates.filter {
            selectedImportCandidateIDs.contains($0.id) && $0.isEligible
        }
        guard !eligibleSelection.isEmpty else {
            return
        }

        let shouldInclude = eligibleSelection.contains {
            !includedImportCandidateIDs.contains($0.id)
        }
        for candidate in eligibleSelection {
            if shouldInclude {
                includedImportCandidateIDs.insert(candidate.id)
            } else {
                includedImportCandidateIDs.remove(candidate.id)
            }
        }
    }

    func beginImportPreview() {
        guard canBeginImportPreview else {
            return
        }
        if let importCoordinator {
            let includedIDs = Set(
                includedImportCandidateIDs.compactMap(UUID.init(uuidString:))
            )
            importCoordinator.beginImport(includedIDs: includedIDs)
            return
        }
        importPreviewStage = .importing
        selectedImportCandidateIDs.removeAll()
        importSelectionAnchorID = nil
    }

    func completeImportPreview() {
        guard importPreviewStage == .importing else {
            return
        }
        importPreviewStage = .complete
    }

    func importMorePreviewMusic() {
        importCoordinator?.cancel()
        importPreviewStage = .empty
        resetImportPreviewCandidates()
    }

    func viewImportedPreviewTracks() {
        if let completion = managedImportCompletion {
            selectedDestination = .library
            Task {
                await librarySession.store.showImportedTracks(
                    importID: completion.importID
                )
            }
            return
        }
        let firstImportedTrackID = importCandidates.first {
            includedImportCandidateIDs.contains($0.id)
                && $0.sourceTrackID != nil
        }?.sourceTrackID

        selectedDestination = .library
        guard
            let firstImportedTrackID,
            let track = tracks.first(where: { $0.id == firstImportedTrackID })
        else {
            return
        }
        selectTrack(track)
    }

    func showImportPreviewStage(_ stage: ImportPreviewStage) {
        guard isImportPreviewMode else {
            return
        }
        isImportPreviewAutoAdvanceEnabled = false
        resetImportPreviewCandidates()

        switch stage {
        case .empty:
            importPreviewStage = .empty
        case .scanning:
            importPreviewStage = .scanning
        case .review:
            importPreviewStage = .review
            selectFirstVisibleImportCandidate()
        case .importing:
            importPreviewStage = .importing
        case .complete:
            importPreviewStage = .complete
        }
    }

    func setImportDropTargeted(_ isTargeted: Bool) {
        isImportDropTargeted = isTargeted
    }

    func acceptImportPreviewDrop() {
        guard isImportPreviewMode else {
            return
        }
        isImportDropTargeted = false
        requestNavigationDestination(.importMusic)
        startImportPreview()
    }

    func acceptImportDrop(urls: [URL]) {
        isImportDropTargeted = false
        requestNavigationDestination(.importMusic)
        guard !isImportPreviewMode else {
            startImportPreview()
            return
        }
        startImportScan(source: ImportSource(urls: urls))
    }

    func clearImportScanError() {
        importScanError = nil
    }

    func clearImportOperationError() {
        importOperationError = nil
    }

    func selectFirstVisibleImportCandidate() {
        guard let firstID = visibleImportCandidates.first?.id else {
            return
        }
        selectedImportCandidateIDs = [firstID]
        importSelectionAnchorID = firstID
    }

    private func toggleImportCandidateSelection(
        _ candidateID: ImportCandidatePreview.ID,
        canonicalOrder: [ImportCandidatePreview.ID]
    ) {
        if selectedImportCandidateIDs.contains(candidateID) {
            selectedImportCandidateIDs.remove(candidateID)
            if importSelectionAnchorID == candidateID {
                importSelectionAnchorID = canonicalOrder.first {
                    selectedImportCandidateIDs.contains($0)
                }
            }
        } else {
            selectedImportCandidateIDs.insert(candidateID)
            importSelectionAnchorID = candidateID
        }
    }

    private func selectImportCandidateRange(
        through candidateID: ImportCandidatePreview.ID,
        canonicalOrder: [ImportCandidatePreview.ID]
    ) {
        guard
            let importSelectionAnchorID,
            let anchorIndex = canonicalOrder.firstIndex(
                of: importSelectionAnchorID
            ),
            let candidateIndex = canonicalOrder.firstIndex(of: candidateID)
        else {
            selectedImportCandidateIDs = [candidateID]
            importSelectionAnchorID = candidateID
            return
        }

        let range = min(anchorIndex, candidateIndex)
            ... max(anchorIndex, candidateIndex)
        selectedImportCandidateIDs = Set(canonicalOrder[range])
    }
}
