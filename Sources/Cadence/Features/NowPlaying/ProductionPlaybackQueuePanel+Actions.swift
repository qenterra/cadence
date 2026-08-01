import AppKit
import SwiftUI

extension ProductionPlaybackQueuePanel {
    var queue: PlaybackQueueState? {
        model.playbackCoordinator?.state.queue
    }

    var orderedTrackIDs: [UUID] {
        queue?.orderedTrackIDs ?? []
    }

    func projection(
        for trackID: UUID
    ) -> PlaybackQueueTrackProjection {
        model.productionPlaybackQueueTracks.first { $0.id == trackID }
            ?? PlaybackQueueTrackProjection(id: trackID, state: .loading)
    }

    func updateSelection(
        _ trackID: UUID,
        canonicalOrder: [UUID]
    ) {
        let modifiers = NSEvent.modifierFlags
        queueHasFocus = true

        if
            modifiers.contains(.shift),
            let selectionAnchor,
            let anchorIndex = canonicalOrder.firstIndex(of: selectionAnchor),
            let targetIndex = canonicalOrder.firstIndex(of: trackID) {
            let range = min(anchorIndex, targetIndex) ... max(
                anchorIndex,
                targetIndex
            )
            selection = Set(canonicalOrder[range])
        } else if modifiers.contains(.command) {
            if selection.contains(trackID) {
                selection.remove(trackID)
            } else {
                selection.insert(trackID)
                selectionAnchor = trackID
            }
        } else {
            selection = [trackID]
            selectionAnchor = trackID
        }
    }

    func removeSelection() {
        guard !selection.isEmpty else {
            return
        }
        if model.removeFromProductionQueue(
            Array(selection),
            undoManager: undoManager
        ) {
            selection.removeAll()
            selectionAnchor = nil
        }
    }

    func removeFromQueue(
        _ trackID: UUID
    ) {
        if model.removeFromProductionQueue(
            [trackID],
            undoManager: undoManager
        ) {
            selection.remove(trackID)
            if selectionAnchor == trackID {
                selectionAnchor = nil
            }
        }
    }

    func moveSelection(
        by offset: Int
    ) {
        guard
            let upNext = queue?.upNextTrackIDs,
            !selection.isEmpty
        else {
            return
        }
        let selectedIndices = upNext.indices.filter {
            selection.contains(upNext[$0])
        }
        guard
            let first = selectedIndices.first,
            let last = selectedIndices.last
        else {
            return
        }

        let targetID: UUID?
        if offset < 0 {
            guard first > upNext.startIndex else {
                return
            }
            targetID = upNext[first - 1]
        } else {
            guard last < upNext.index(before: upNext.endIndex) else {
                return
            }
            let targetIndex = last + 2
            targetID = upNext.indices.contains(targetIndex)
                ? upNext[targetIndex]
                : nil
        }

        _ = model.reorderProductionQueue(
            upNext.filter(selection.contains),
            before: targetID,
            undoManager: undoManager
        )
    }

    func canMoveSelection(
        by offset: Int
    ) -> Bool {
        guard
            let upNext = queue?.upNextTrackIDs,
            !selection.isEmpty
        else {
            return false
        }
        let selectedIndices = upNext.indices.filter {
            selection.contains(upNext[$0])
        }
        if offset < 0 {
            return selectedIndices.first.map { $0 > upNext.startIndex } == true
        }
        return selectedIndices.last.map {
            $0 < upNext.index(before: upNext.endIndex)
        } == true
    }

    func dragPayload(
        for trackID: UUID
    ) -> String {
        let ids: [UUID] = if selection.contains(trackID),
                             let upNext = queue?.upNextTrackIDs {
            upNext.filter(selection.contains)
        } else {
            [trackID]
        }
        return ids.map(\.uuidString).joined(separator: ",")
    }

    func reorder(
        payloads: [String],
        before targetID: UUID?
    ) -> Bool {
        let ids = payloads.flatMap { payload in
            payload.split(separator: ",").compactMap {
                UUID(uuidString: String($0))
            }
        }
        activeDropTarget = nil
        return model.reorderProductionQueue(
            ids,
            before: targetID,
            undoManager: undoManager
        )
    }

    func queueSectionHeader(
        _ title: String
    ) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(CadenceTheme.separator)
                    .frame(height: 1)
            }
    }

    func emptyMessage(
        for kind: ProductionQueueSectionKind
    ) -> String {
        switch kind {
        case .history:
            "Nothing played before the current track."
        case .current:
            "No current track."
        case .upNext:
            "The current track will finish without another item."
        }
    }

    func queueSourceTitle(
        _ source: PlaybackQueueSource
    ) -> String {
        switch source {
        case .album:
            "Album snapshot"
        case .artist:
            "Artist snapshot"
        case .smartCollection:
            "Smart Collection snapshot"
        case .playlist:
            "Playlist snapshot"
        case .allTracks:
            "Library snapshot"
        case .adHoc:
            "Manual queue"
        }
    }
}
