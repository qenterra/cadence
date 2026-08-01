import Foundation

extension CadenceAppModel {
    var selectedSmartCollectionCanonicalTracks: [TrackPreview] {
        guard let selectedSmartCollection else {
            return []
        }
        return evaluateSmartCollection(rule: selectedSmartCollection.rule)
    }

    var selectedSmartCollectionSortDescriptor: SmartCollectionSortDescriptor {
        guard let selectedSmartCollectionID else {
            return .canonical
        }
        return smartCollectionSortDescriptors[selectedSmartCollectionID]
            ?? .canonical
    }

    var selectedSmartCollectionVisibleTracks: [TrackPreview] {
        SmartCollectionListeningProjection.sortedTracks(
            selectedSmartCollectionCanonicalTracks,
            by: selectedSmartCollectionSortDescriptor
        )
    }

    var selectedSmartCollectionDuration: TimeInterval {
        SmartCollectionListeningProjection.totalDuration(
            of: selectedSmartCollectionCanonicalTracks
        )
    }

    var selectedSmartCollectionArtwork: SmartCollectionArtworkLayout {
        SmartCollectionListeningProjection.artworkLayout(
            for: selectedSmartCollectionCanonicalTracks
        )
    }

    var smartCollectionListItems: [SmartCollectionListItem] {
        var items = smartCollections.map { collection in
            let isSelected = collection.id == selectedSmartCollectionID
            let selectedDraft = smartCollectionDraft.flatMap {
                $0.sourceID == collection.id ? $0 : nil
            }
            let name = selectedDraft?.name ?? collection.name
            let matchCount: Int
            let totalDuration: TimeInterval
            if librarySession.availability != .preview {
                let summary = librarySession.store.smartCollectionSummary(
                    for: selectedDraft?.rule ?? collection.rule
                )
                matchCount = summary.count
                totalDuration = summary.totalDuration
            } else {
                let matchingTracks = selectedDraft == nil
                    ? evaluateSmartCollection(rule: collection.rule)
                    : smartCollectionLiveTracks
                matchCount = matchingTracks.count
                totalDuration = SmartCollectionListeningProjection
                    .totalDuration(of: matchingTracks)
            }

            return SmartCollectionListItem(
                id: collection.id,
                name: name,
                matchCount: matchCount,
                totalDuration: totalDuration,
                isTransient: false,
                isSelected: isSelected
            )
        }

        if let draft = smartCollectionDraft, draft.sourceID == nil {
            let matchCount: Int
            let totalDuration: TimeInterval
            if librarySession.availability != .preview {
                matchCount = productionSmartCollectionLiveSummary.count
                totalDuration = productionSmartCollectionLiveSummary
                    .totalDuration
            } else {
                matchCount = smartCollectionLiveTracks.count
                totalDuration = SmartCollectionListeningProjection
                    .totalDuration(of: smartCollectionLiveTracks)
            }
            items.append(
                SmartCollectionListItem(
                    id: draft.id,
                    name: draft.name,
                    matchCount: matchCount,
                    totalDuration: totalDuration,
                    isTransient: true,
                    isSelected: true
                )
            )
        }
        return items
    }

    func smartCollectionMatchCount(
        for collection: SmartCollectionPreview
    ) -> Int {
        evaluateSmartCollection(rule: collection.rule).count
    }

    func prepareInitialSmartCollection() {
        selectedSmartCollectionID = smartCollections.first?.id
        smartCollectionsPresentationMode = .listening
        smartCollectionDraft = nil
        lastValidSmartCollectionResultIDs = []
    }

    @discardableResult
    func requestEditSelectedSmartCollection() -> Bool {
        guard let selectedSmartCollection else {
            return false
        }
        loadSmartCollectionDraft(selectedSmartCollection)
        smartCollectionsPresentationMode = .editing
        return true
    }

    func requestFinishSmartCollectionEditing() {
        requestSmartCollectionTransition(.listening)
    }

    func requestNewSmartCollection(
        draftID: UUID = UUID(),
        rootID: UUID = UUID()
    ) {
        requestSmartCollectionTransition(
            .new(draftID: draftID, rootID: rootID)
        )
    }

    func requestSelectSmartCollection(
        _ collectionID: SmartCollectionPreview.ID
    ) {
        let isAlreadySelected = collectionID == selectedSmartCollectionID
            && (
                smartCollectionsPresentationMode == .listening
                    || smartCollectionDraft?.sourceID == collectionID
            )
        guard
            !isAlreadySelected,
            smartCollections.contains(where: { $0.id == collectionID })
        else {
            return
        }
        requestSmartCollectionTransition(.collection(collectionID))
    }

    func requestRenameSmartCollection(
        _ collectionID: SmartCollectionPreview.ID
    ) {
        guard smartCollections.contains(where: { $0.id == collectionID }) else {
            return
        }

        let isEditingCollection = smartCollectionsPresentationMode == .editing
            && smartCollectionDraft?.sourceID == collectionID
        if isEditingCollection {
            smartCollectionNameFocusRequest = UUID()
        } else {
            requestSmartCollectionTransition(.rename(collectionID))
        }
    }

    func consumeSmartCollectionNameFocusRequest(_ request: UUID?) {
        guard smartCollectionNameFocusRequest == request else {
            return
        }
        smartCollectionNameFocusRequest = nil
    }

    func requestNavigationDestination(_ destination: NavigationDestination) {
        if requestPlaybackWorkspaceNavigation(destination) {
            return
        }
        guard destination != selectedDestination else {
            clearProductionDetailRoute(for: destination)
            return
        }
        contextualNavigationHistory.removeAll()
        selectedProductionArtistID = nil
        selectedProductionAlbumID = nil
        selectedProductionTagID = nil

        let isLeavingEditor = selectedDestination == .smartCollections
            && smartCollectionsPresentationMode == .editing
        if isLeavingEditor {
            requestSmartCollectionTransition(.destination(destination))
            return
        }

        selectedDestination = destination
        if destination == .smartCollections {
            enterSmartCollectionsListening()
        } else if destination == .albums {
            prepareAlbumsDestination()
        } else if destination == .artists {
            prepareArtistsDestination()
        }
    }

    private func clearProductionDetailRoute(
        for destination: NavigationDestination
    ) {
        switch destination {
        case .artists:
            selectedProductionArtistID = nil
        case .albums:
            selectedProductionAlbumID = nil
        case .tags:
            selectedProductionTagID = nil
        default:
            return
        }
        contextualNavigationHistory.removeAll()
    }

    @discardableResult
    func resolvePendingSmartCollectionTransition(
        _ resolution: SmartCollectionSwitchResolution,
        modifiedAt: Date = .now
    ) -> Bool {
        guard let target = pendingSmartCollectionTransition else {
            return false
        }

        switch resolution {
        case .cancel:
            pendingSmartCollectionTransition = nil
            return true
        case .discard:
            pendingSmartCollectionTransition = nil
            performSmartCollectionTransition(target)
            return true
        case .save:
            guard saveSmartCollectionDraft(modifiedAt: modifiedAt) else {
                return false
            }
            pendingSmartCollectionTransition = nil
            performSmartCollectionTransition(target)
            return true
        }
    }

    func activateSelectedSmartCollectionSort(
        _ field: SmartCollectionSortField
    ) {
        guard let selectedSmartCollectionID else {
            return
        }
        var descriptor = selectedSmartCollectionSortDescriptor
        descriptor.activate(field)
        smartCollectionSortDescriptors[selectedSmartCollectionID] = descriptor
    }

    private func requestSmartCollectionTransition(
        _ target: SmartCollectionTransitionTarget
    ) {
        let requiresConfirmation = smartCollectionsPresentationMode == .editing
            && isSmartCollectionDraftDirty
        if requiresConfirmation {
            pendingSmartCollectionTransition = target
        } else {
            performSmartCollectionTransition(target)
        }
    }

    private func performSmartCollectionTransition(
        _ target: SmartCollectionTransitionTarget
    ) {
        switch target {
        case let .collection(collectionID):
            guard let collection = smartCollections.first(where: {
                $0.id == collectionID
            }) else {
                return
            }
            selectedSmartCollectionID = collection.id
            previousSavedSmartCollectionID = collection.id
            if smartCollectionsPresentationMode == .editing {
                loadSmartCollectionDraft(collection)
            } else {
                smartCollectionDraft = nil
                lastValidSmartCollectionResultIDs = []
            }
        case let .new(draftID, rootID):
            previousSavedSmartCollectionID = selectedSmartCollectionID
                ?? previousSavedSmartCollectionID
            selectedSmartCollectionID = nil
            smartCollectionsPresentationMode = .editing
            smartCollectionDraft = SmartCollectionDraft(
                id: draftID,
                sourceID: nil,
                name: "Untitled Collection",
                rule: SmartCollectionRuleGroup(
                    id: rootID,
                    combinator: .all,
                    children: []
                )
            )
            lastValidSmartCollectionResultIDs = tracks.map(\.id)
        case .listening:
            enterSmartCollectionsListening()
        case let .rename(collectionID):
            guard let collection = smartCollections.first(where: {
                $0.id == collectionID
            }) else {
                return
            }
            selectedSmartCollectionID = collection.id
            previousSavedSmartCollectionID = collection.id
            smartCollectionsPresentationMode = .editing
            loadSmartCollectionDraft(collection)
            smartCollectionNameFocusRequest = UUID()
        case let .destination(destination):
            enterSmartCollectionsListening()
            selectedDestination = destination
        case let .contextualRoute(route):
            finishSmartCollectionTransition(to: route)
        }
    }

    private func finishSmartCollectionTransition(
        to route: ContextualMediaRoute
    ) {
        enterSmartCollectionsListening()
        performContextualNavigation(route)
    }

    private func enterSmartCollectionsListening() {
        if selectedSmartCollectionID == nil {
            let restoredID = previousSavedSmartCollectionID.flatMap { id in
                smartCollections.contains(where: { $0.id == id }) ? id : nil
            }
            selectedSmartCollectionID = restoredID ?? smartCollections.first?.id
        }
        previousSavedSmartCollectionID = selectedSmartCollectionID
        smartCollectionsPresentationMode = .listening
        smartCollectionDraft = nil
        lastValidSmartCollectionResultIDs = []
    }
}
