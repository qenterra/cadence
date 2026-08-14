import Foundation

extension CadenceAppModel {
    func openTagEditor(for track: TrackPreview) {
        guard tracks.contains(where: { $0.id == track.id }) else {
            return
        }
        contextualNavigationHistory.removeAll()

        let effectiveTags = effectiveTags(for: track)
        let anchorTag = effectiveTags.first {
            $0.id == selectedTagID
        } ?? effectiveTags.first
        let target = TagAssignmentTarget.track(track.id)

        selectedDestination = .tags
        selectedTagGroupID = .all
        selectedTagID = anchorTag?.id
        tagResultScope = .tracks
        tagEditingSelection.apply(
            .replace,
            target: target,
            canonicalOrder: [target]
        )
        isLibraryTagEditingContext = true
        selectTrack(track)
        isTagInspectorPresented = true
    }

    var canSelectAllTagResults: Bool {
        !canonicalTagTargets(for: activeTagResultKind).isEmpty
    }

    func selectAllTagResults() {
        let targets = canonicalTagTargets(for: activeTagResultKind)
        guard !targets.isEmpty else {
            return
        }

        isLibraryTagEditingContext = false
        tagEditingSelection.selectAll(canonicalOrder: targets)
        syncLibrarySelectionToPrimaryTagTarget()
    }

    private var activeTagResultKind: TagEditingTargetKind {
        switch tagResultScope {
        case .tracks:
            .tracks
        case .albums:
            .albums
        }
    }
}
