import SwiftUI

struct PlaybackQueuePanel: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.undoManager) var undoManager
    @State var activeDropTarget: PlaybackQueueDropTarget?
    @State var draggedTrackID: TrackPreview.ID?
    @State var selection: Set<TrackPreview.ID> = []
    @State var selectionAnchor: TrackPreview.ID?
    @State var showsHistory = false
    @FocusState var queueHasFocus: Bool

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
