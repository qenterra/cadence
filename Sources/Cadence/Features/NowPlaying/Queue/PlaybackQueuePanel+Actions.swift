import AppKit
import SwiftUI

extension PlaybackQueuePanel {
    func reorderDragged(
        _ values: [String],
        before targetTrackID: TrackPreview.ID?
    ) -> Bool {
        model.reorderPlaybackQueue(
            values.compactMap(Int.init),
            before: targetTrackID,
            undoManager: undoManager
        )
    }

    func removeSelection() {
        guard !selection.isEmpty else {
            return
        }
        model.removeFromPlaybackQueue(
            Array(selection),
            undoManager: undoManager
        )
        selection.removeAll()
        selectionAnchor = nil
    }

    func removeFromQueue(_ trackID: TrackPreview.ID) {
        model.removeFromPlaybackQueue(
            [trackID],
            undoManager: undoManager
        )
        selection.remove(trackID)
        if selectionAnchor == trackID {
            selectionAnchor = nil
        }
    }

    func updateSelection(
        _ trackID: TrackPreview.ID,
        canonicalOrder: [TrackPreview.ID]
    ) {
        let modifiers = NSEvent.modifierFlags
        queueHasFocus = true

        if let range = shiftSelectionRange(
            for: trackID,
            in: canonicalOrder,
            modifiers: modifiers
        ) {
            selection = Set(canonicalOrder[range])
            return
        }

        if modifiers.contains(.command) {
            toggleSelection(trackID, canonicalOrder: canonicalOrder)
            return
        }

        selection = [trackID]
        selectionAnchor = trackID
    }

    func moveSelection(by offset: Int) {
        guard
            let upNext = model.activePlaybackQueue?.upNextTrackIDs,
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

        let targetID: TrackPreview.ID?
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

        model.reorderPlaybackQueue(
            Array(selection),
            before: targetID,
            undoManager: undoManager
        )
    }

    func canMoveSelection(by offset: Int) -> Bool {
        guard
            let upNext = model.activePlaybackQueue?.upNextTrackIDs,
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

    func tracks(
        for trackIDs: [TrackPreview.ID]
    ) -> [TrackPreview] {
        trackIDs.compactMap(track(for:))
    }

    func track(
        for trackID: TrackPreview.ID?
    ) -> TrackPreview? {
        guard let trackID else {
            return nil
        }
        return model.tracks.first { $0.id == trackID }
    }

    func queueSourceTitle(
        _ source: PlaybackQueue.Source
    ) -> String {
        switch source {
        case .album:
            "Album snapshot"
        case .artist:
            "Artist snapshot"
        case .smartCollection:
            "Smart Collection snapshot"
        case .adHoc:
            "Manual queue"
        }
    }

    func queueSectionHeader(_ title: String) -> some View {
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

    var queueRowSeparator: some View {
        Rectangle()
            .fill(CadenceTheme.separator)
            .frame(height: 1)
    }

    private func shiftSelectionRange(
        for trackID: TrackPreview.ID,
        in canonicalOrder: [TrackPreview.ID],
        modifiers: NSEvent.ModifierFlags
    ) -> ClosedRange<Int>? {
        guard
            modifiers.contains(.shift),
            let selectionAnchor,
            let anchorIndex = canonicalOrder.firstIndex(of: selectionAnchor),
            let targetIndex = canonicalOrder.firstIndex(of: trackID)
        else {
            return nil
        }
        return min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
    }

    private func toggleSelection(
        _ trackID: TrackPreview.ID,
        canonicalOrder: [TrackPreview.ID]
    ) {
        if selection.contains(trackID) {
            selection.remove(trackID)
            if selectionAnchor == trackID {
                selectionAnchor = canonicalOrder.first {
                    selection.contains($0)
                }
            }
        } else {
            selection.insert(trackID)
            selectionAnchor = trackID
        }
    }
}
