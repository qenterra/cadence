import SwiftUI

enum PlaybackQueueDropTarget: Equatable {
    case track(TrackPreview.ID)
    case end

    var insertionTrackID: TrackPreview.ID? {
        switch self {
        case let .track(trackID):
            trackID
        case .end:
            nil
        }
    }
}

struct PlaybackQueueDropDelegate: DropDelegate {
    let target: PlaybackQueueDropTarget

    @Binding var draggedTrackID: TrackPreview.ID?
    @Binding var activeTarget: PlaybackQueueDropTarget?

    let reorder: ([String], TrackPreview.ID?) -> Bool

    func validateDrop(info _: DropInfo) -> Bool {
        draggedTrackID != nil
    }

    func dropEntered(info _: DropInfo) {
        activeTarget = target
    }

    func dropExited(info _: DropInfo) {
        guard activeTarget == target else {
            return
        }
        activeTarget = nil
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        guard let draggedTrackID else {
            activeTarget = nil
            return false
        }

        let didReorder = reorder(
            [String(draggedTrackID)],
            target.insertionTrackID
        )
        activeTarget = nil
        self.draggedTrackID = nil
        return didReorder
    }
}

struct PlaybackQueueInsertionIndicator: View {
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

struct PlaybackQueueDragPreview: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview

    var body: some View {
        HStack(spacing: 10) {
            MediaArtworkView(
                source: model.resolvedArtwork(for: track),
                title: track.title,
                placeholder: .track,
                cornerRadius: 5
            )
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(track.artist) · \(track.album)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(width: 330)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CadenceTheme.opaqueSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        }
        .shadow(color: .black.opacity(0.38), radius: 16, y: 8)
    }
}
