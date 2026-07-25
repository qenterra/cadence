import SwiftUI

struct PlaybackQueueRow: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview
    let isCurrent: Bool
    let isDraggable: Bool

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                palette: track.artworkPalette,
                title: track.title,
                cornerRadius: 6
            )
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.callout.weight(isCurrent ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(track.artist) · \(track.album)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            Text(track.durationText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? "Current track" : "")
    }
}
