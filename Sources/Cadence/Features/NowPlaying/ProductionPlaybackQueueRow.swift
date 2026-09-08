import QenTerraMediaComponents
import SwiftUI

struct ProductionPlaybackQueueRow: View {
    @Bindable var model: CadenceAppModel

    let item: PlaybackQueueTrackProjection
    let isCurrent: Bool
    let isSelected: Bool
    let dragPayload: String?
    let select: (() -> Void)?
    let play: () -> Void
    let remove: (() -> Void)?

    var body: some View {
        QenTerraMediaComponents.PlaybackQueueRow(
            presentation: presentation,
            dragPayload: dragPayload,
            select: select,
            play: play,
            remove: remove,
            artwork: { artwork },
            metadata: { metadata },
            contextMenu: { contextMenu },
            dragPreview: { dragPreview }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
        }
    }
}

private extension ProductionPlaybackQueueRow {
    var presentation: PlaybackQueueRowPresentation<UUID> {
        CadencePlayerAdapters.queueRow(
            CadenceQueueRowSnapshot(
                id: item.id,
                title: item.track?.title ?? stateTitle,
                subtitle: item.track.map { "\($0.artist) · \($0.album)" } ?? stateDetail,
                durationText: item.track.map { TrackPreview.timeText($0.duration) },
                isAvailable: item.track != nil
            ),
            isCurrent: isCurrent,
            isSelected: isSelected,
            isDraggable: dragPayload != nil,
            isPlaying: isCurrent && model.isPlaying
        )
    }

    @ViewBuilder
    var artwork: some View {
        if let track = item.track {
            ProductionArtworkView(
                model: model,
                artworkID: track.artworkID,
                title: track.title,
                placeholder: .track,
                cornerRadius: CadenceTheme.radiusControl
            )
        } else {
            RoundedRectangle(cornerRadius: CadenceTheme.radiusControl)
                .fill(CadenceTheme.secondarySurface)
                .overlay {
                    stateIcon.foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    var metadata: some View {
        if let track = item.track {
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
                        guard let artistID = track.artistID else { return }
                        model.requestOpenProductionArtistContextually(id: artistID)
                    }
                    Text(" · ")
                    MediaMetadataLink(
                        track.album,
                        accessibilityLabel: "Open album \(track.album)"
                    ) {
                        guard let albumID = track.albumID else { return }
                        model.requestOpenProductionAlbumContextually(id: albumID)
                    }
                }
            }
        } else {
            Text(stateDetail)
        }
    }

    @ViewBuilder
    var contextMenu: some View {
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
                item.track == nil ? "Remove Unavailable Item" : "Remove from Queue",
                systemImage: "minus.circle",
                action: remove
            )
        }
    }

    var dragPreview: some View {
        QueueDragPreview(
            title: item.track?.title ?? "Unavailable Track",
            subtitle: item.track.map { "\($0.artist) · \($0.album)" } ?? item.id.uuidString,
            artwork: { artwork }
        )
    }

    @ViewBuilder
    var stateIcon: some View {
        switch item.state {
        case .loading:
            ProgressView().controlSize(.small)
        case .available:
            Image(systemName: "music.note")
        case .unavailable:
            Image(systemName: "questionmark.folder")
        case .failed:
            Image(systemName: "exclamationmark.triangle")
        }
    }

    var stateTitle: String {
        switch item.state {
        case .loading: "Loading Track…"
        case .available: "Track"
        case .unavailable: "Track Unavailable"
        case .failed: "Couldn’t Load Track"
        }
    }

    var stateDetail: String {
        switch item.state {
        case .loading: item.id.uuidString
        case .available: ""
        case .unavailable: "The library no longer contains this queue item."
        case let .failed(message): message
        }
    }
}
