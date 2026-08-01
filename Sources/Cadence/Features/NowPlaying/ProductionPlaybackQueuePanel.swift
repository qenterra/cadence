import AppKit
import SwiftUI

struct ProductionPlaybackQueuePanel: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.undoManager) private var undoManager
    @State private var selection: Set<UUID> = []
    @State private var selectionAnchor: UUID?
    @State private var activeDropTarget: ProductionQueueDropTarget?
    @FocusState private var queueHasFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            queueHeader
            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            if let queue {
                queueList(queue)
            } else {
                ContentUnavailableView {
                    Label("Queue Is Empty", systemImage: "list.bullet")
                } description: {
                    Text("Play a track to create a playback queue.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: orderedTrackIDs) {
            await model.loadProductionPlaybackQueueTracks()
        }
        .onDeleteCommand(perform: removeSelection)
    }

    private var queueHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playback Queue")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(queue.map { queueSourceTitle($0.source) } ?? "No active queue")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Move Up", systemImage: "arrow.up") {
                moveSelection(by: -1)
            }
            .labelStyle(.iconOnly)
            .disabled(!canMoveSelection(by: -1))

            Button("Move Down", systemImage: "arrow.down") {
                moveSelection(by: 1)
            }
            .labelStyle(.iconOnly)
            .disabled(!canMoveSelection(by: 1))

            Button("Remove", systemImage: "minus") {
                removeSelection()
            }
            .disabled(selection.isEmpty)

            Button("Clear", systemImage: "clear") {
                if model.clearProductionQueue(undoManager: undoManager) {
                    selection.removeAll()
                    selectionAnchor = nil
                }
            }
            .disabled(queue?.upNextTrackIDs.isEmpty != false)
        }
        .guideAnchor(.queue)
        .buttonStyle(.borderless)
        .padding(.horizontal, 24)
        .frame(height: 58)
    }

    private func queueList(
        _ queue: PlaybackQueueState
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                queueSection(
                    title: "History",
                    ids: queue.previouslyPlayedTrackIDs,
                    kind: .history
                )
                queueSection(
                    title: "Now Playing",
                    ids: [queue.currentTrackID].compactMap(\.self),
                    kind: .current
                )
                queueSection(
                    title: "Up Next",
                    ids: queue.upNextTrackIDs,
                    kind: .upNext
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($queueHasFocus)
        .onKeyPress("a", phases: .down) { keyPress in
            guard keyPress.modifiers == .command else {
                return .ignored
            }
            selection = Set(queue.upNextTrackIDs)
            selectionAnchor = queue.upNextTrackIDs.first
            return .handled
        }
        .onKeyPress(.return, phases: .down) { _ in
            guard
                let trackID = queue.upNextTrackIDs.first(
                    where: selection.contains
                ),
                projection(for: trackID).track != nil
            else {
                return .ignored
            }
            model.playProductionQueueItem(id: trackID)
            return .handled
        }
        .onChange(of: queue.upNextTrackIDs) {
            selection.formIntersection(queue.upNextTrackIDs)
            if selectionAnchor.map({
                !queue.upNextTrackIDs.contains($0)
            }) == true {
                selectionAnchor = queue.upNextTrackIDs.first {
                    selection.contains($0)
                }
            }
        }
    }

    @ViewBuilder
    private func queueSection(
        title: String,
        ids: [UUID],
        kind: ProductionQueueSectionKind
    ) -> some View {
        queueSectionHeader(
            ids.isEmpty ? title : "\(title) · \(ids.count.formatted())"
        )

        if ids.isEmpty {
            Text(emptyMessage(for: kind))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 16)
        } else {
            ForEach(ids, id: \.self) { trackID in
                queueRow(
                    projection(for: trackID),
                    kind: kind,
                    canonicalOrder: ids
                )
            }
        }

        if kind == .upNext {
            Color.clear
                .frame(height: 16)
                .overlay(alignment: .top) {
                    if activeDropTarget == .end {
                        ProductionQueueInsertionIndicator()
                    }
                }
                .dropDestination(for: String.self) { payloads, _ in
                    reorder(payloads: payloads, before: nil)
                } isTargeted: { isTargeted in
                    activeDropTarget = isTargeted ? .end : nil
                }
                .accessibilityLabel("End of Up Next")
        }
    }

    private func queueRow(
        _ item: PlaybackQueueTrackProjection,
        kind: ProductionQueueSectionKind,
        canonicalOrder: [UUID]
    ) -> some View {
        let isUpNext = kind == .upNext
        let isSelected = isUpNext && selection.contains(item.id)

        return ProductionPlaybackQueueRow(
            model: model,
            item: item,
            isCurrent: kind == .current,
            isSelected: isSelected,
            isDraggable: isUpNext,
            play: {
                guard item.track != nil else {
                    return
                }
                model.playProductionQueueItem(id: item.id)
            },
            remove: isUpNext ? {
                removeFromQueue(item.id)
            } : nil
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            BrowserRowSurface(
                isSelected: isSelected,
                isHovered: false,
                isFocused: false
            )
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    guard item.track != nil else {
                        return
                    }
                    model.playProductionQueueItem(id: item.id)
                }
        )
        .highPriorityGesture(
            TapGesture()
                .onEnded {
                    guard isUpNext else {
                        return
                    }
                    updateSelection(
                        item.id,
                        canonicalOrder: canonicalOrder
                    )
                }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
        }
        .overlay(alignment: .top) {
            if activeDropTarget == .track(item.id) {
                ProductionQueueInsertionIndicator()
            }
        }
        .modifier(
            ProductionQueueDragModifier(
                payload: dragPayload(for: item.id),
                item: item,
                isEnabled: isUpNext
            )
        )
        .dropDestination(for: String.self) { payloads, _ in
            guard isUpNext else {
                return false
            }
            return reorder(payloads: payloads, before: item.id)
        } isTargeted: { isTargeted in
            guard isUpNext else {
                return
            }
            activeDropTarget = isTargeted ? .track(item.id) : nil
        }
    }
}

private extension ProductionPlaybackQueuePanel {
    private var queue: PlaybackQueueState? {
        model.playbackCoordinator?.state.queue
    }

    private var orderedTrackIDs: [UUID] {
        queue?.orderedTrackIDs ?? []
    }

    private func projection(
        for trackID: UUID
    ) -> PlaybackQueueTrackProjection {
        model.productionPlaybackQueueTracks.first { $0.id == trackID }
            ?? PlaybackQueueTrackProjection(id: trackID, state: .loading)
    }

    private func updateSelection(
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

    private func removeSelection() {
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

    private func removeFromQueue(
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

    private func moveSelection(
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

    private func canMoveSelection(
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

    private func dragPayload(
        for trackID: UUID
    ) -> String {
        let ids: [UUID] = if selection.contains(trackID), let upNext = queue?.upNextTrackIDs {
            upNext.filter(selection.contains)
        } else {
            [trackID]
        }
        return ids.map(\.uuidString).joined(separator: ",")
    }

    private func reorder(
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

    private func queueSectionHeader(
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

    private func emptyMessage(
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

    private func queueSourceTitle(
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

private enum ProductionQueueSectionKind {
    case history
    case current
    case upNext
}

private enum ProductionQueueDropTarget: Equatable {
    case track(UUID)
    case end
}

private struct ProductionQueueInsertionIndicator: View {
    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.9))
            .frame(height: 2)
            .padding(.horizontal, 8)
            .offset(y: -1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct ProductionQueueDragModifier: ViewModifier {
    let payload: String
    let item: PlaybackQueueTrackProjection
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(payload) {
                ProductionQueueDragPreview(item: item)
            }
        } else {
            content
        }
    }
}

private struct ProductionQueueDragPreview: View {
    let item: PlaybackQueueTrackProjection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.track == nil ? "questionmark" : "music.note")
                .frame(width: 38, height: 38)
                .background(CadenceTheme.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.track?.title ?? "Unavailable Track")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(item.track.map { "\($0.artist) · \($0.album)" }
                    ?? item.id.uuidString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(width: 330, alignment: .leading)
        .background(CadenceTheme.opaqueSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.14))
        }
        .shadow(color: .black.opacity(0.38), radius: 16, y: 8)
    }
}
