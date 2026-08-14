import Foundation

extension CadenceAppModel {
    func updateTagEditingSelection(
        _ gesture: TagSelectionGesture,
        target: TagAssignmentTarget
    ) {
        isLibraryTagEditingContext = false
        let canonicalOrder = canonicalTagTargets(for: target.editingKind)
        tagEditingSelection.apply(
            gesture,
            target: target,
            canonicalOrder: canonicalOrder
        )

        guard !tagEditingSelection.isEmpty else {
            isTagInspectorPresented = false
            return
        }

        syncLibrarySelectionToPrimaryTagTarget()
    }

    func clearTagEditingSelection(closeInspector: Bool = true) {
        tagEditingSelection.clear()
        isLibraryTagEditingContext = false
        if closeInspector {
            isTagInspectorPresented = false
        }
    }

    func pruneTagEditingSelection() {
        let validTargets = isLibraryTagEditingContext
            ? libraryTagTargets(for: tagEditingSelection.kind)
            : canonicalTagTargets(for: tagEditingSelection.kind)
        tagEditingSelection.prune(
            validTargets: validTargets
        )
        if tagEditingSelection.isEmpty {
            isTagInspectorPresented = false
        }
    }

    func openTagInspector(for target: TagAssignmentTarget? = nil) {
        if let target {
            guard canonicalTagTargets(for: target.editingKind).contains(target) else {
                return
            }
            if !tagEditingSelection.contains(target) {
                updateTagEditingSelection(.replace, target: target)
            }
        }
        guard !tagEditingSelection.isEmpty else {
            return
        }
        isTagInspectorPresented = true
    }

    func toggleTagInspector() {
        guard !tagEditingSelection.isEmpty else {
            return
        }
        isTagInspectorPresented.toggle()
    }

    @discardableResult
    func performTagEdit(
        _ command: TagEditCommand,
        undoManager: UndoManager? = nil
    ) -> Bool {
        let before = tagEditingSnapshot
        guard applyTagEdit(command) else {
            return false
        }

        pruneTagEditingSelection()
        if let undoManager {
            registerTagUndo(
                restoring: before,
                actionName: command.actionName,
                undoManager: undoManager
            )
        }
        return true
    }

    private var tagEditingSnapshot: TagEditingSnapshot {
        TagEditingSnapshot(
            tags: tags,
            assignments: tagAssignments,
            exclusions: tagExclusions,
            dismissals: dismissedTagSuggestions,
            selection: tagEditingSelection,
            isInspectorPresented: isTagInspectorPresented,
            isLibraryContext: isLibraryTagEditingContext,
            context: tagBrowsingContext
        )
    }

    private var tagBrowsingContext: TagBrowsingContext {
        TagBrowsingContext(
            groupID: selectedTagGroupID,
            tagID: selectedTagID,
            scope: tagResultScope
        )
    }

    private func registerTagUndo(
        restoring snapshot: TagEditingSnapshot,
        actionName: String,
        undoManager: UndoManager
    ) {
        undoManager.registerUndo(withTarget: self) { model in
            let inverse = model.tagEditingSnapshot
            model.restoreTagEditingSnapshot(snapshot)
            model.registerTagUndo(
                restoring: inverse,
                actionName: actionName,
                undoManager: undoManager
            )
        }
        undoManager.setActionName(actionName)
    }

    private func restoreTagEditingSnapshot(_ snapshot: TagEditingSnapshot) {
        let canRestoreSelection = tagBrowsingContext == snapshot.context
        replaceTagEditingState(
            tags: snapshot.tags,
            assignments: snapshot.assignments,
            exclusions: snapshot.exclusions,
            dismissals: snapshot.dismissals
        )

        if canRestoreSelection {
            tagEditingSelection = snapshot.selection
            isTagInspectorPresented = snapshot.isInspectorPresented
            isLibraryTagEditingContext = snapshot.isLibraryContext
            pruneTagEditingSelection()
        }
    }

    private func applyTagEdit(_ command: TagEditCommand) -> Bool {
        switch command {
        case let .assign(tagID, targets):
            assign(tagID: tagID, to: targets)
        case let .acceptSuggestion(tagID, targets):
            acceptSuggestion(tagID: tagID, targets: targets)
        case let .removeDirect(tagID, targets):
            removeDirect(tagID: tagID, from: targets)
        case let .createAndAssign(path, targets):
            createAndAssign(path: path, targets: targets)
        case let .excludeInherited(tagID, trackIDs):
            excludeInherited(tagID: tagID, trackIDs: trackIDs)
        case let .restoreInheritance(tagID, trackIDs):
            restoreInheritance(tagID: tagID, trackIDs: trackIDs)
        case let .dismissSuggestion(tagID, targets):
            dismissSuggestion(tagID: tagID, targets: targets)
        }
    }

    private func acceptSuggestion(
        tagID: TagPreview.ID,
        targets: [TagAssignmentTarget]
    ) -> Bool {
        guard let currentSuggestion = tagSuggestions(for: targets)
            .first(where: { $0.tag.id == tagID })
        else {
            return false
        }
        return assign(tagID: tagID, to: currentSuggestion.eligibleTargets)
    }

    private func assign(
        tagID: TagPreview.ID,
        to targets: [TagAssignmentTarget]
    ) -> Bool {
        guard tags.contains(where: { $0.id == tagID }) else {
            return false
        }

        let validTargets = targets.filter(isValidTagTarget)
        let assignments = validTargets.map {
            TagAssignmentPreview(tagID: tagID, target: $0)
        }
        return insertTagAssignmentsForEditing(assignments)
    }

    private func removeDirect(
        tagID: TagPreview.ID,
        from targets: [TagAssignmentTarget]
    ) -> Bool {
        let validTargets = targets.filter(isValidTagTarget)
        return removeTagAssignmentsForEditing(
            validTargets.map {
                TagAssignmentPreview(tagID: tagID, target: $0)
            }
        )
    }

    private func createAndAssign(
        path: String,
        targets: [TagAssignmentTarget]
    ) -> Bool {
        guard let tag = TagPreview(path: path) else {
            return false
        }

        let createdTag = insertTagForEditing(tag)
        let assigned = assign(tagID: tag.id, to: targets)
        return createdTag || assigned
    }

    private func excludeInherited(
        tagID: TagPreview.ID,
        trackIDs: [TrackPreview.ID]
    ) -> Bool {
        let applicableTrackIDs = trackIDs.filter { trackID in
            guard let track = tracks.first(where: { $0.id == trackID }) else {
                return false
            }
            return tagMatchSource(for: track, tagID: tagID) == .inherited
        }
        return insertTagExclusionsForEditing(
            applicableTrackIDs.map {
                TagExclusionPreview(tagID: tagID, trackID: $0)
            }
        )
    }

    private func restoreInheritance(
        tagID: TagPreview.ID,
        trackIDs: [TrackPreview.ID]
    ) -> Bool {
        let validTrackIDs = trackIDs.filter { trackID in
            tracks.contains { $0.id == trackID }
        }
        return removeTagExclusionsForEditing(
            validTrackIDs.map {
                TagExclusionPreview(tagID: tagID, trackID: $0)
            }
        )
    }

    private func dismissSuggestion(
        tagID: TagPreview.ID,
        targets: [TagAssignmentTarget]
    ) -> Bool {
        insertTagDismissalsForEditing(
            targets.filter(isValidTagTarget).map {
                TagSuggestionDismissal(tagID: tagID, target: $0)
            }
        )
    }

    func canonicalTagTargets(
        for kind: TagEditingTargetKind?
    ) -> [TagAssignmentTarget] {
        switch kind {
        case .tracks:
            taggedTracks.map { .track($0.track.id) }
        case .albums:
            taggedAlbums.map { .album($0.album.id) }
        case nil:
            []
        }
    }

    private func libraryTagTargets(
        for kind: TagEditingTargetKind?
    ) -> [TagAssignmentTarget] {
        switch kind {
        case .tracks:
            tracks.map { .track($0.id) }
        case .albums:
            albums.map { .album($0.id) }
        case nil:
            []
        }
    }

    func syncLibrarySelectionToPrimaryTagTarget() {
        switch tagEditingSelection.primaryTarget {
        case let .track(trackID):
            if let track = tracks.first(where: { $0.id == trackID }) {
                selectTrack(track)
            }
        case let .album(albumID):
            if let album = albums.first(where: { $0.id == albumID }) {
                selectAlbum(album)
            }
        case nil:
            break
        }
    }

    private func isValidTagTarget(_ target: TagAssignmentTarget) -> Bool {
        switch target {
        case let .track(trackID):
            tracks.contains { $0.id == trackID }
        case let .album(albumID):
            albums.contains { $0.id == albumID }
        }
    }
}

private struct TagBrowsingContext: Equatable {
    let groupID: TagGroupID
    let tagID: TagPreview.ID?
    let scope: TagResultScope
}

private struct TagEditingSnapshot {
    let tags: [TagPreview]
    let assignments: Set<TagAssignmentPreview>
    let exclusions: Set<TagExclusionPreview>
    let dismissals: Set<TagSuggestionDismissal>
    let selection: TagEditingSelection
    let isInspectorPresented: Bool
    let isLibraryContext: Bool
    let context: TagBrowsingContext
}
