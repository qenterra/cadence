import SwiftUI

extension ProductionPlaybackQueuePanel {
    func queueList(
        _ queue: PlaybackQueueState
    ) -> some View {
        queueScrollContent(queue)
            .focusable()
            .focusEffectDisabled()
            .focused($queueHasFocus)
            .onKeyPress("a", phases: .down) { keyPress in
                selectAllUpNext(keyPress, queue: queue)
            }
            .onKeyPress(.return, phases: .down) { _ in
                playSelectedQueueItem(queue)
            }
            .onChange(
                of: PlaybackQueuePresentation.upNextTrackIDs(for: queue)
            ) {
                reconcileSelection(
                    with: PlaybackQueuePresentation.upNextTrackIDs(for: queue)
                )
            }
    }

    @ViewBuilder
    func queueSection(
        title: String,
        ids: [UUID],
        kind: ProductionQueueSectionKind,
        showsTitle: Bool = true
    ) -> some View {
        if showsTitle {
            queueSectionHeader(
                ids.isEmpty ? title : "\(title) · \(ids.count.formatted())"
            )
        }

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
            queueEndDropTarget
        }
    }

    func queueRow(
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
            play: { play(item) },
            remove: isUpNext ? { removeFromQueue(item.id) } : nil
        )
        .modifier(
            ProductionQueueRowInteractionModifier(
                isUpNext: isUpNext,
                isSelected: isSelected,
                play: { play(item) },
                select: {
                    updateSelection(
                        item.id,
                        canonicalOrder: canonicalOrder
                    )
                }
            )
        )
        .modifier(
            ProductionQueueRowDropModifier(
                item: item,
                isUpNext: isUpNext,
                payload: dragPayload(for: item.id),
                activeDropTarget: $activeDropTarget,
                reorder: { payloads in
                    reorder(payloads: payloads, before: item.id)
                }
            )
        )
    }
}

private extension ProductionPlaybackQueuePanel {
    func queueScrollContent(
        _ queue: PlaybackQueueState
    ) -> some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                queueSection(
                    title: "Now Playing",
                    ids: [queue.currentTrackID].compactMap(\.self),
                    kind: .current
                )
                queueSection(
                    title: "Up Next",
                    ids: PlaybackQueuePresentation.upNextTrackIDs(for: queue),
                    kind: .upNext,
                    showsTitle: NowPlayingPanelPresentation
                        .showsUpNextSectionTitle
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
    }

    var queueEndDropTarget: some View {
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

    func selectAllUpNext(
        _ keyPress: KeyPress,
        queue: PlaybackQueueState
    ) -> KeyPress.Result {
        guard keyPress.modifiers == .command else {
            return .ignored
        }
        let visibleIDs = PlaybackQueuePresentation.upNextTrackIDs(for: queue)
        selection = Set(visibleIDs)
        selectionAnchor = visibleIDs.first
        return .handled
    }

    func playSelectedQueueItem(
        _ queue: PlaybackQueueState
    ) -> KeyPress.Result {
        let visibleIDs = PlaybackQueuePresentation.upNextTrackIDs(for: queue)
        guard
            let trackID = visibleIDs.first(where: selection.contains),
            projection(for: trackID).track != nil
        else {
            return .ignored
        }
        model.playProductionQueueItem(id: trackID)
        return .handled
    }

    func reconcileSelection(
        with upNextTrackIDs: [UUID]
    ) {
        selection.formIntersection(upNextTrackIDs)
        if selectionAnchor.map({ !upNextTrackIDs.contains($0) }) == true {
            selectionAnchor = upNextTrackIDs.first(where: selection.contains)
        }
    }

    func play(
        _ item: PlaybackQueueTrackProjection
    ) {
        guard item.track != nil else {
            return
        }
        model.playProductionQueueItem(id: item.id)
    }
}
