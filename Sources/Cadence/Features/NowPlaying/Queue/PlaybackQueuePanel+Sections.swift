import SwiftUI
import UniformTypeIdentifiers

extension PlaybackQueuePanel {
    func queueList(_ queue: PlaybackQueue) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                historySection(queue)
                currentSection(queue)
                upNextSection(queue)
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
    private func historySection(_ queue: PlaybackQueue) -> some View {
        if !queue.previouslyPlayedTrackIDs.isEmpty {
            DisclosureGroup(
                isExpanded: $showsHistory
            ) {
                LazyVStack(spacing: 0) {
                    ForEach(
                        tracks(for: queue.previouslyPlayedTrackIDs)
                    ) { track in
                        PlaybackQueueRow(
                            model: model,
                            track: track,
                            isCurrent: false,
                            isDraggable: false,
                            isSelected: false,
                            onDragStarted: nil
                        )
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) {
                            queueRowSeparator
                        }
                    }
                }
            } label: {
                Text(
                    "Previously Played · "
                        + queue.previouslyPlayedTrackIDs.count.formatted()
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func currentSection(_ queue: PlaybackQueue) -> some View {
        if let currentTrack = track(for: queue.currentTrackID) {
            queueSectionHeader("Current")

            PlaybackQueueRow(
                model: model,
                track: currentTrack,
                isCurrent: true,
                isDraggable: false,
                isSelected: false,
                onDragStarted: nil
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                queueRowSeparator
            }
        }
    }

    @ViewBuilder
    private func upNextSection(_ queue: PlaybackQueue) -> some View {
        queueSectionHeader(
            queue.upNextTrackIDs.isEmpty
                ? "Up Next"
                : "Up Next · \(queue.upNextTrackIDs.count)"
        )

        if queue.upNextTrackIDs.isEmpty {
            emptyUpNext
        } else {
            upNextRows(queue)
        }
    }

    private var emptyUpNext: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Nothing Up Next")
                .font(.callout.weight(.medium))
            Text("The current track will finish without another item.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private func upNextRows(_ queue: PlaybackQueue) -> some View {
        ForEach(tracks(for: queue.upNextTrackIDs)) { track in
            upNextRow(track, queue: queue)
        }

        Color.clear
            .frame(height: 16)
            .overlay(alignment: .top) {
                if activeDropTarget == .end {
                    PlaybackQueueInsertionIndicator()
                }
            }
            .onDrop(
                of: [UTType.utf8PlainText],
                delegate: PlaybackQueueDropDelegate(
                    target: .end,
                    draggedTrackID: $draggedTrackID,
                    activeTarget: $activeDropTarget,
                    reorder: reorderDragged(_:before:)
                )
            )
            .accessibilityLabel("End of Up Next")
    }

    private func upNextRow(
        _ track: TrackPreview,
        queue: PlaybackQueue
    ) -> some View {
        upNextRowSurface(track)
            .onDisappear {
                if draggedTrackID == track.id {
                    draggedTrackID = nil
                }
            }
            .contextMenu {
                ArtworkMenuItems(
                    model: model,
                    target: .track(track.id),
                    label: "Track Artwork"
                )

                Divider()

                Button("Remove from Queue", systemImage: "minus") {
                    removeFromQueue(track.id)
                }
            }
            .highPriorityGesture(
                TapGesture()
                    .onEnded {
                        updateSelection(
                            track.id,
                            canonicalOrder: queue.upNextTrackIDs
                        )
                    }
            )
    }

    private func upNextRowSurface(
        _ track: TrackPreview
    ) -> some View {
        PlaybackQueueRow(
            model: model,
            track: track,
            isCurrent: false,
            isDraggable: true,
            isSelected: selection.contains(track.id),
            onDragStarted: {
                draggedTrackID = track.id
            }
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            BrowserRowSurface(
                isSelected: selection.contains(track.id),
                isHovered: false,
                isFocused: false
            )
        }
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            queueRowSeparator
        }
        .overlay(alignment: .top) {
            if activeDropTarget == .track(track.id) {
                PlaybackQueueInsertionIndicator()
            }
        }
        .onDrop(
            of: [UTType.utf8PlainText],
            delegate: PlaybackQueueDropDelegate(
                target: .track(track.id),
                draggedTrackID: $draggedTrackID,
                activeTarget: $activeDropTarget,
                reorder: reorderDragged(_:before:)
            )
        )
    }
}
