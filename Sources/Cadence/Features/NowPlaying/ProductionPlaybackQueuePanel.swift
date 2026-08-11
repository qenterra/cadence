import SwiftUI

struct ProductionPlaybackQueuePanel: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.undoManager) var undoManager
    @State var selection: Set<UUID> = []
    @State var selectionAnchor: UUID?
    @State var activeDropTarget: ProductionQueueDropTarget?
    @FocusState var queueHasFocus: Bool

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
        .task(id: visibleTrackIDs) {
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
            .disabled(queue?.hasUpNext != true)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 24)
        .frame(height: 58)
    }
}
