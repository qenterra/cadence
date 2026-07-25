import SwiftUI

struct PlaybackQueuePanel: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.undoManager) private var undoManager
    @State private var selection: Set<TrackPreview.ID> = []
    @State private var showsHistory = false

    var body: some View {
        VStack(spacing: 0) {
            queueHeader

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            if let queue = model.activePlaybackQueue {
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
        .onDeleteCommand {
            removeSelection()
        }
    }

    private var queueHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playback Queue")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if let queue = model.activePlaybackQueue {
                    Text(queueSourceTitle(queue.source))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                moveSelection(by: -1)
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(!canMoveSelection(by: -1))
            .help("Move Up")

            Button {
                moveSelection(by: 1)
            } label: {
                Image(systemName: "arrow.down")
            }
            .disabled(!canMoveSelection(by: 1))
            .help("Move Down")

            Button("Remove", systemImage: "minus") {
                removeSelection()
            }
            .disabled(selection.isEmpty)

            Button("Clear", systemImage: "clear") {
                model.clearPlaybackQueue(undoManager: undoManager)
                selection.removeAll()
            }
            .disabled(model.activePlaybackQueue?.upNextTrackIDs.isEmpty != false)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 24)
        .frame(height: 58)
    }
}

private extension PlaybackQueuePanel {
    private func queueList(_ queue: PlaybackQueue) -> some View {
        List(selection: $selection) {
            historySection(queue)
            currentSection(queue)
            upNextSection(queue)
        }
        .listStyle(.inset)
        .onChange(of: queue.upNextTrackIDs) {
            selection.formIntersection(queue.upNextTrackIDs)
        }
    }

    @ViewBuilder
    private func historySection(_ queue: PlaybackQueue) -> some View {
        if !queue.previouslyPlayedTrackIDs.isEmpty {
            Section {
                DisclosureGroup(
                    isExpanded: $showsHistory
                ) {
                    ForEach(
                        tracks(for: queue.previouslyPlayedTrackIDs)
                    ) { track in
                        PlaybackQueueRow(
                            model: model,
                            track: track,
                            isCurrent: false,
                            isDraggable: false
                        )
                        .foregroundStyle(.secondary)
                    }
                } label: {
                    Text(
                        "Previously Played · "
                            + queue.previouslyPlayedTrackIDs.count.formatted()
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func currentSection(_ queue: PlaybackQueue) -> some View {
        if let currentTrack = track(for: queue.currentTrackID) {
            Section("Current") {
                PlaybackQueueRow(
                    model: model,
                    track: currentTrack,
                    isCurrent: true,
                    isDraggable: false
                )
            }
        }
    }

    private func upNextSection(_ queue: PlaybackQueue) -> some View {
        Section {
            if queue.upNextTrackIDs.isEmpty {
                emptyUpNext
            } else {
                upNextRows(queue)
            }
        } header: {
            Text(
                queue.upNextTrackIDs.isEmpty
                    ? "Up Next"
                    : "Up Next · \(queue.upNextTrackIDs.count)"
            )
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
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private func upNextRows(_ queue: PlaybackQueue) -> some View {
        ForEach(tracks(for: queue.upNextTrackIDs)) { track in
            PlaybackQueueRow(
                model: model,
                track: track,
                isCurrent: false,
                isDraggable: true
            )
            .tag(track.id)
            .draggable(String(track.id))
            .dropDestination(for: String.self) { values, _ in
                reorderDragged(values, before: track.id)
            }
            .contextMenu {
                Button("Remove from Queue", systemImage: "minus") {
                    model.removeFromPlaybackQueue(
                        [track.id],
                        undoManager: undoManager
                    )
                    selection.remove(track.id)
                }
            }
        }

        Color.clear
            .frame(height: 16)
            .dropDestination(for: String.self) { values, _ in
                reorderDragged(values, before: nil)
            }
            .accessibilityLabel("End of Up Next")
    }

    private func reorderDragged(
        _ values: [String],
        before targetTrackID: TrackPreview.ID?
    ) -> Bool {
        model.reorderPlaybackQueue(
            values.compactMap(Int.init),
            before: targetTrackID,
            undoManager: undoManager
        )
    }

    private func removeSelection() {
        guard !selection.isEmpty else {
            return
        }
        model.removeFromPlaybackQueue(
            Array(selection),
            undoManager: undoManager
        )
        selection.removeAll()
    }

    private func moveSelection(by offset: Int) {
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

    private func canMoveSelection(by offset: Int) -> Bool {
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

    private func tracks(
        for trackIDs: [TrackPreview.ID]
    ) -> [TrackPreview] {
        trackIDs.compactMap(track(for:))
    }

    private func track(
        for trackID: TrackPreview.ID?
    ) -> TrackPreview? {
        guard let trackID else {
            return nil
        }
        return model.tracks.first { $0.id == trackID }
    }

    private func queueSourceTitle(
        _ source: PlaybackQueue.Source
    ) -> String {
        switch source {
        case .album:
            "Album snapshot"
        case .smartCollection:
            "Smart Collection snapshot"
        case .adHoc:
            "Manual queue"
        }
    }
}
