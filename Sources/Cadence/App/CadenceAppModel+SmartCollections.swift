import Foundation

extension CadenceAppModel {
    var selectedSmartCollection: SmartCollectionPreview? {
        smartCollections.first { $0.id == selectedSmartCollectionID }
    }

    var smartCollectionValidation: SmartCollectionValidationResult {
        guard let smartCollectionDraft else {
            return SmartCollectionValidationResult(issues: [])
        }
        return SmartCollectionValidator.validate(
            draft: smartCollectionDraft,
            savedCollections: smartCollections
        )
    }

    var isSmartCollectionDraftDirty: Bool {
        guard let smartCollectionDraft else {
            return false
        }
        return smartCollectionDraft.isDirty(comparedTo: selectedSmartCollection)
    }

    var canSaveSmartCollectionDraft: Bool {
        smartCollectionsPresentationMode == .editing
            && smartCollectionDraft != nil
            && isSmartCollectionDraftDirty
            && smartCollectionValidation.isValid
    }

    var canRevertSmartCollectionDraft: Bool {
        smartCollectionsPresentationMode == .editing
            && smartCollectionDraft?.sourceID != nil
            && isSmartCollectionDraftDirty
    }

    var smartCollectionRuleOptions: SmartCollectionRuleOptions {
        if librarySession.availability != .preview {
            return librarySession.store.smartCollectionRuleData.options
        }

        return SmartCollectionRuleOptions(
            tagIDs: tags
                .sorted {
                    $0.displayPath.localizedStandardCompare($1.displayPath)
                        == .orderedAscending
                }
                .map(\.id),
            artists: artists.map(\.name),
            albums: albums.map(\.title),
            years: Array(Set(tracks.map(\.year))).sorted(by: >),
            formats: Array(Set(tracks.map(\.format))).sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        )
    }

    var smartCollectionLiveTracks: [TrackPreview] {
        guard
            smartCollectionsPresentationMode == .editing,
            let smartCollectionDraft
        else {
            return []
        }
        if smartCollectionValidation.isValid {
            return evaluateSmartCollection(rule: smartCollectionDraft.rule)
        }

        let tracksByID = Dictionary(
            uniqueKeysWithValues: tracks.map { ($0.id, $0) }
        )
        return lastValidSmartCollectionResultIDs.compactMap {
            tracksByID[$0]
        }
    }

    var productionSmartCollectionLiveTracks: [LibraryTrackProjection] {
        guard
            librarySession.availability != .preview,
            smartCollectionsPresentationMode == .editing,
            let smartCollectionDraft,
            smartCollectionValidation.isValid
        else {
            return []
        }
        return librarySession.store.smartCollectionTracks(
            for: smartCollectionDraft.rule
        )
    }

    var selectedProductionSmartCollectionTracks:
        [LibraryTrackProjection] {
        guard
            librarySession.availability != .preview,
            let selectedSmartCollection
        else {
            return []
        }
        return librarySession.store.smartCollectionTracks(
            for: selectedSmartCollection.rule
        )
    }

    var productionSmartCollectionLiveSummary:
        ProductionSmartCollectionSummary {
        guard
            let smartCollectionDraft,
            smartCollectionValidation.isValid
        else {
            return .empty
        }
        return librarySession.store.smartCollectionSummary(
            for: smartCollectionDraft.rule
        )
    }

    var selectedProductionSmartCollectionSummary:
        ProductionSmartCollectionSummary {
        guard let selectedSmartCollection else {
            return .empty
        }
        return librarySession.store.smartCollectionSummary(
            for: selectedSmartCollection.rule
        )
    }

    func playSelectedProductionSmartCollection(
        shuffled: Bool = false
    ) {
        guard let selectedSmartCollection else {
            return
        }
        Task {
            var collectionTracks = await librarySession.store
                .completeSmartCollectionTracks(
                    for: selectedSmartCollection.rule
                )
            if shuffled {
                collectionTracks.shuffle()
            }
            guard let first = collectionTracks.first else {
                return
            }
            playProductionTrack(
                first,
                within: collectionTracks,
                source: selectedSmartCollectionID.map {
                    .smartCollection($0)
                }
            )
        }
    }

    func renameSmartCollectionDraft(_ name: String) {
        mutateSmartCollectionDraft {
            $0.name = name
        }
    }

    func requestEditSmartCollection(
        _ collectionID: SmartCollectionPreview.ID
    ) {
        if smartCollectionsPresentationMode == .editing {
            requestSelectSmartCollection(collectionID)
            return
        }

        requestSelectSmartCollection(collectionID)
        guard selectedSmartCollectionID == collectionID else {
            return
        }
        requestEditSelectedSmartCollection()
    }

    @discardableResult
    func saveSmartCollectionDraft(
        modifiedAt: Date = .now
    ) -> Bool {
        guard let saved = validatedSmartCollection(modifiedAt: modifiedAt) else {
            return false
        }
        applySavedSmartCollection(saved)
        return true
    }

    @discardableResult
    func saveSmartCollectionDraftPersisting(
        modifiedAt: Date = .now
    ) async -> Bool {
        guard let saved = validatedSmartCollection(modifiedAt: modifiedAt) else {
            return false
        }
        if librarySession.availability != .preview {
            guard await librarySession.store.savePersistedSmartCollection(saved) else {
                return false
            }
        }
        applySavedSmartCollection(saved)
        return true
    }

    func loadPersistedSmartCollections() async {
        guard librarySession.availability != .preview else {
            return
        }
        guard let persisted = await librarySession.store.persistedSmartCollections() else {
            return
        }
        smartCollections = persisted
        prepareInitialSmartCollection()
    }

    private func validatedSmartCollection(
        modifiedAt: Date
    ) -> SmartCollectionPreview? {
        guard
            let draft = smartCollectionDraft,
            SmartCollectionValidator.validate(
                draft: draft,
                savedCollections: smartCollections
            ).isValid
        else {
            return nil
        }
        return SmartCollectionPreview(
            id: draft.sourceID ?? draft.id,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            rule: draft.rule,
            modifiedAt: modifiedAt
        )
    }

    private func applySavedSmartCollection(_ saved: SmartCollectionPreview) {
        if let index = smartCollections.firstIndex(where: {
            $0.id == saved.id
        }) {
            smartCollections[index] = saved
        } else {
            smartCollections.append(saved)
        }

        selectedSmartCollectionID = saved.id
        previousSavedSmartCollectionID = saved.id
        smartCollectionDraft = SmartCollectionDraft(collection: saved)
        lastValidSmartCollectionResultIDs = evaluateSmartCollection(
            rule: saved.rule
        ).map(\.id)
    }

    @discardableResult
    func revertSmartCollectionDraft() -> Bool {
        guard
            let sourceID = smartCollectionDraft?.sourceID,
            let collection = smartCollections.first(where: {
                $0.id == sourceID
            })
        else {
            return false
        }
        loadSmartCollectionDraft(collection)
        return true
    }

    func requestDeleteSmartCollection(
        _ collectionID: SmartCollectionPreview.ID
    ) {
        guard smartCollections.contains(where: { $0.id == collectionID }) else {
            return
        }
        pendingSmartCollectionDeletionID = collectionID
    }

    func cancelDeleteSmartCollection() {
        pendingSmartCollectionDeletionID = nil
    }

    @discardableResult
    func confirmDeleteSmartCollection() -> Bool {
        guard
            let collectionID = pendingSmartCollectionDeletionID,
            let index = smartCollections.firstIndex(where: {
                $0.id == collectionID
            })
        else {
            return false
        }

        applySmartCollectionDeletion(collectionID, at: index)
        return true
    }

    @discardableResult
    func confirmDeleteSmartCollectionPersisting() async -> Bool {
        guard
            let collectionID = pendingSmartCollectionDeletionID,
            let index = smartCollections.firstIndex(where: {
                $0.id == collectionID
            })
        else {
            return false
        }
        if librarySession.availability != .preview {
            guard await librarySession.store.deletePersistedSmartCollection(
                id: collectionID
            ) else {
                return false
            }
        }
        applySmartCollectionDeletion(collectionID, at: index)
        return true
    }

    private func applySmartCollectionDeletion(
        _ collectionID: SmartCollectionPreview.ID,
        at index: Int
    ) {
        smartCollections.remove(at: index)
        smartCollectionSortDescriptors[collectionID] = nil
        pendingSmartCollectionDeletionID = nil

        let removedActiveCollection = selectedSmartCollectionID == collectionID
            || smartCollectionDraft?.sourceID == collectionID
        guard removedActiveCollection else {
            return
        }

        guard !smartCollections.isEmpty else {
            selectedSmartCollectionID = nil
            previousSavedSmartCollectionID = nil
            smartCollectionDraft = nil
            smartCollectionsPresentationMode = .listening
            lastValidSmartCollectionResultIDs = []
            return
        }

        let nextIndex = min(index, smartCollections.count - 1)
        selectedSmartCollectionID = smartCollections[nextIndex].id
        previousSavedSmartCollectionID = selectedSmartCollectionID
        smartCollectionDraft = nil
        smartCollectionsPresentationMode = .listening
        lastValidSmartCollectionResultIDs = []
    }

    func mutateSmartCollectionDraft(
        _ mutation: (inout SmartCollectionDraft) -> Void
    ) {
        guard var draft = smartCollectionDraft else {
            return
        }

        let oldValidation = SmartCollectionValidator.validate(
            draft: draft,
            savedCollections: smartCollections
        )
        if oldValidation.isValid {
            lastValidSmartCollectionResultIDs = evaluateSmartCollection(
                rule: draft.rule
            ).map(\.id)
        }

        mutation(&draft)
        smartCollectionDraft = draft

        let newValidation = SmartCollectionValidator.validate(
            draft: draft,
            savedCollections: smartCollections
        )
        if newValidation.isValid {
            lastValidSmartCollectionResultIDs = evaluateSmartCollection(
                rule: draft.rule
            ).map(\.id)
        }
    }

    func loadSmartCollectionDraft(
        _ collection: SmartCollectionPreview
    ) {
        selectedSmartCollectionID = collection.id
        smartCollectionDraft = SmartCollectionDraft(collection: collection)
        lastValidSmartCollectionResultIDs = evaluateSmartCollection(
            rule: collection.rule
        ).map(\.id)
    }

    func evaluateSmartCollection(
        rule: SmartCollectionRuleGroup
    ) -> [TrackPreview] {
        SmartCollectionRuleEvaluator().evaluate(
            root: rule,
            tracks: tracks,
            context: smartCollectionEvaluationContext
        )
    }

    private var smartCollectionEvaluationContext: SmartCollectionEvaluationContext {
        SmartCollectionEvaluationContext(
            effectiveTagsByTrackID: Dictionary(
                uniqueKeysWithValues: tracks.map {
                    ($0.id, effectiveTags(for: $0))
                }
            ),
            tagsByID: Dictionary(
                uniqueKeysWithValues: tags.map { ($0.id, $0) }
            ),
            favoriteTrackIDs: favoriteTrackIDs
        )
    }
}
