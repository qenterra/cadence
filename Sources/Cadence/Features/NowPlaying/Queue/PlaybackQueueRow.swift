import SwiftUI

struct PlaybackQueueRow: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview
    let isCurrent: Bool
    let isDraggable: Bool
    let isSelected: Bool
    let onDragStarted: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            MediaArtworkView(
                source: model.resolvedArtwork(for: track),
                title: track.title,
                placeholder: .track,
                cornerRadius: 6
            )
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.callout.weight(isCurrent ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    MediaMetadataLink(
                        track.artist,
                        accessibilityLabel: "Open artist \(track.artist)"
                    ) {
                        model.requestOpenArtistContextually(id: track.artistID)
                    }

                    Text(" · ")

                    MediaMetadataLink(
                        track.album,
                        accessibilityLabel: "Open album \(track.album)"
                    ) {
                        model.requestOpenAlbumContextually(id: track.albumID)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if isCurrent {
                Image(
                    systemName: model.isPlaying
                        ? "waveform"
                        : "speaker.fill"
                )
                .font(.caption)
                .foregroundStyle(.primary)
                .accessibilityLabel(model.isPlaying ? "Playing" : "Paused")
            } else if isDraggable {
                PlaybackQueueDragHandle(
                    model: model,
                    track: track,
                    onDragStarted: onDragStarted
                )
            }

            Text(track.durationText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityValue(isCurrent ? "Current track" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            ArtworkMenuItems(
                model: model,
                target: .track(track.id),
                label: "Track Artwork"
            )

            Button("Edit Tags", systemImage: "tag") {
                model.dismissNowPlaying()
                model.openTagEditor(for: track)
            }
        }
    }
}

private struct PlaybackQueueDragHandle: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview
    let onDragStarted: (() -> Void)?

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(width: 28, height: 42)
            .contentShape(Rectangle())
            .onDrag {
                onDragStarted?()
                return NSItemProvider(
                    object: String(track.id) as NSString
                )
            } preview: {
                PlaybackQueueDragPreview(
                    model: model,
                    track: track
                )
            }
            .help("Drag to reorder")
            .accessibilityLabel("Reorder \(track.title)")
    }
}
