import SwiftUI

struct ProductionPlaybackQueuePanel: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(queueDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Up Next") {
                    model.clearProductionQueue()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(upNextIDs.isEmpty)
            }
            .padding(.horizontal, 28)
            .frame(height: 48)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.productionPlaybackQueueTracks) { track in
                        ProductionPlaybackQueueRow(
                            model: model,
                            track: track,
                            isCurrent: model.currentPlaybackTrack?.id
                                == track.id,
                            isUpNext: upNextIDs.contains(track.id)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    private var upNextIDs: Set<UUID> {
        Set(
            model.playbackCoordinator?
                .state.queue?
                .upNextTrackIDs
                ?? []
        )
    }

    private var queueDetail: String {
        let count = model.playbackCoordinator?
            .state.queue?
            .orderedTrackIDs.count
            ?? 0
        return "\(count) tracks"
    }
}

private struct ProductionPlaybackQueueRow: View {
    @Bindable var model: CadenceAppModel
    let track: LibraryTrackProjection
    let isCurrent: Bool
    let isUpNext: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.playProductionQueueItem(id: track.id)
            } label: {
                ProductionArtworkView(
                    model: model,
                    artworkID: track.artworkID,
                    title: track.title,
                    placeholder: .track,
                    cornerRadius: 6
                )
                .frame(width: 40, height: 40)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(
                            cornerRadius: 6,
                            style: .continuous
                        )
                        .fill(.black.opacity(0.34))
                        Image(
                            systemName: model.isPlaying
                                ? "waveform"
                                : "speaker.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Play \(track.title)")

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    model.playProductionQueueItem(id: track.id)
                } label: {
                    Text(track.title)
                        .font(
                            .body.weight(
                                isCurrent ? .semibold : .regular
                            )
                        )
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                queueMetadata
            }

            Spacer()

            Text(TrackPreview.timeText(track.duration))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(isHovered ? .primary : .tertiary)
                    .frame(width: 28, height: 28)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .help("Track Actions")
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .background(isHovered ? CadenceTheme.hoverFill : .clear)
        .onHover { isHovered = $0 }
        .draggable(track.id.uuidString) {
            HStack(spacing: 9) {
                ProductionArtworkView(
                    model: model,
                    artworkID: track.artworkID,
                    title: track.title,
                    placeholder: .track,
                    cornerRadius: 5
                )
                .frame(width: 32, height: 32)
                Text(track.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .frame(maxWidth: 280, alignment: .leading)
            .background(CadenceTheme.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        CadenceTheme.separator,
                        lineWidth: 0.5
                    )
            }
        }
        .dropDestination(for: String.self) { values, _ in
            let trackIDs = values.compactMap(UUID.init(uuidString:))
            return model.reorderProductionQueue(
                trackIDs,
                before: track.id
            )
        }
        .contextMenu {
            actions
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
                .padding(.leading, 52)
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Play Now", systemImage: "play.fill") {
            model.playProductionQueueItem(id: track.id)
        }
        Button("Edit Tags…", systemImage: "tag.badge.plus") {
            model.openProductionTagEditor(trackID: track.id)
        }
        QuickTrackTagMenuItems(
            store: model.librarySession.store,
            trackID: track.id
        )
        AddToPlaylistMenuItems(
            store: model.librarySession.store,
            trackIDs: [track.id]
        )
        ArtworkMenuItems(
            model: model,
            target: .managedTrack(track.id),
            label: "Track Artwork"
        )
        if isUpNext {
            Button("Remove from Queue", systemImage: "minus.circle") {
                model.removeFromProductionQueue([track.id])
            }
        }
        Divider()
        Button(
            "Move to Trash…",
            systemImage: "trash",
            role: .destructive
        ) {
            model.requestLibraryDeletion(
                kind: .track,
                id: track.id,
                title: track.title
            )
        }
    }

    private var queueMetadata: some View {
        HStack(spacing: 5) {
            MediaMetadataLink(
                track.artist,
                accessibilityLabel: "Open artist \(track.artist)"
            ) {
                guard let artistID = track.artistID else {
                    return
                }
                model.requestOpenProductionArtistContextually(id: artistID)
            }
            Text("·")
                .foregroundStyle(.tertiary)
            MediaMetadataLink(
                track.album,
                accessibilityLabel: "Open album \(track.album)"
            ) {
                guard let albumID = track.albumID else {
                    return
                }
                model.requestOpenProductionAlbumContextually(id: albumID)
            }
        }
        .font(.caption)
    }
}
