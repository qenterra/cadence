import SwiftUI

struct ProductionPlaybackQueueRow: View {
    @Bindable var model: CadenceAppModel

    let item: PlaybackQueueTrackProjection
    let isCurrent: Bool
    let isSelected: Bool
    let isDraggable: Bool
    let play: () -> Void
    let remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            artwork
            trackDetails
            Spacer(minLength: 12)
            trailingState
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityValue(isCurrent ? "Current track" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            contextMenu
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let track = item.track {
            ProductionArtworkView(
                model: model,
                artworkID: track.artworkID,
                title: track.title,
                placeholder: .track,
                cornerRadius: CadenceTheme.radiusControl
            )
            .frame(width: 42, height: 42)
        } else {
            RoundedRectangle(cornerRadius: CadenceTheme.radiusControl)
                .fill(CadenceTheme.secondarySurface)
                .frame(width: 42, height: 42)
                .overlay {
                    stateIcon
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private var trackDetails: some View {
        if let track = item.track {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.callout.weight(isCurrent ? .semibold : .medium))
                    .lineLimit(1)

                HStack(spacing: 0) {
                    if model.isCurrentPlaybackExternal {
                        Text(track.artist)
                        Text(" · ")
                        Text(track.album)
                    } else {
                        MediaMetadataLink(
                            track.artist,
                            accessibilityLabel: "Open artist \(track.artist)"
                        ) {
                            guard let artistID = track.artistID else {
                                return
                            }
                            model.requestOpenProductionArtistContextually(
                                id: artistID
                            )
                        }
                        Text(" · ")
                        MediaMetadataLink(
                            track.album,
                            accessibilityLabel: "Open album \(track.album)"
                        ) {
                            guard let albumID = track.albumID else {
                                return
                            }
                            model.requestOpenProductionAlbumContextually(
                                id: albumID
                            )
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(stateTitle)
                    .font(.callout.weight(.medium))
                Text(stateDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var trailingState: some View {
        if isCurrent {
            Image(systemName: model.isPlaying ? "waveform" : "speaker.fill")
                .font(.caption)
                .accessibilityLabel(model.isPlaying ? "Playing" : "Paused")
        } else if isDraggable {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 28, height: 42)
                .help("Drag to reorder")
        }

        if let track = item.track {
            Text(TrackPreview.timeText(track.duration))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let track = item.track {
            Button("Play Now", systemImage: "play.fill", action: play)
            if !model.isCurrentPlaybackExternal {
                Button("Edit Tags…", systemImage: "tag.badge.plus") {
                    model.openProductionTagEditor(trackID: track.id)
                }
                AddToPlaylistMenuItems(
                    model: model,
                    store: model.librarySession.store,
                    trackIDs: [track.id]
                )
                ArtworkMenuItems(
                    model: model,
                    target: .managedTrack(track.id),
                    label: "Track Artwork"
                )
            }
        }
        if let remove {
            Divider()
            Button(
                item.track == nil
                    ? "Remove Unavailable Item"
                    : "Remove from Queue",
                systemImage: "minus.circle",
                action: remove
            )
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch item.state {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .available:
            Image(systemName: "music.note")
        case .unavailable:
            Image(systemName: "questionmark.folder")
        case .failed:
            Image(systemName: "exclamationmark.triangle")
        }
    }

    private var stateTitle: String {
        switch item.state {
        case .loading:
            "Loading Track…"
        case .available:
            "Track"
        case .unavailable:
            "Track Unavailable"
        case .failed:
            "Couldn’t Load Track"
        }
    }

    private var stateDetail: String {
        switch item.state {
        case .loading:
            item.id.uuidString
        case .available:
            ""
        case .unavailable:
            "The library no longer contains this queue item."
        case let .failed(message):
            message
        }
    }
}
