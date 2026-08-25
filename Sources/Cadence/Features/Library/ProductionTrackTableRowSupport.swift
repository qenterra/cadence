import SwiftUI

extension ProductionTrackTableRow {
    var dragPayload: String {
        track.id.uuidString
    }

    static func artworkOverlaySymbolName(
        isCurrentTrack: Bool,
        isPlaying: Bool
    ) -> String {
        isCurrentTrack && isPlaying ? "waveform" : "play.fill"
    }

    var songMetadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(track.title)
                    .font(
                        .body.weight(
                            model.isCurrentProductionTrack(track.id)
                                ? .semibold
                                : .regular
                        )
                    )
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if track.isExplicit {
                    Text("E")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            CadenceTheme.subduedFill,
                            in: RoundedRectangle(
                                cornerRadius: CadenceTheme.radiusControl,
                                style: .continuous
                            )
                        )
                        .accessibilityLabel("Explicit")
                }
            }

            MediaMetadataLink(
                track.artist,
                accessibilityLabel: "Open \(track.artist)"
            ) {
                guard let artistID = track.artistID else {
                    return
                }
                model.requestOpenProductionArtistContextually(
                    id: artistID
                )
            }
            .font(.caption)
            .disabled(track.artistID == nil)
        }
    }

    var lightweightSongMetadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(track.title)
                    .font(
                        .body.weight(
                            model.isCurrentProductionTrack(track.id)
                                ? .semibold
                                : .regular
                        )
                    )
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if track.isExplicit {
                    Text("E")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            CadenceTheme.subduedFill,
                            in: RoundedRectangle(
                                cornerRadius: CadenceTheme.radiusControl,
                                style: .continuous
                            )
                        )
                        .accessibilityLabel("Explicit")
                }
            }

            Text(track.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    func columnValue(
        _ column: TrackTableColumn
    ) -> some View {
        switch column {
        case .album:
            MediaMetadataLink(
                track.album,
                accessibilityLabel: "Open \(track.album)"
            ) {
                guard let albumID = track.albumID else {
                    return
                }
                model.requestOpenProductionAlbumContextually(id: albumID)
            }
            .disabled(track.albumID == nil)
        case .year:
            Text(
                track.year?.formatted(.number.grouping(.never))
                    ?? "—"
            )
        case .time:
            Text(timeText(track.duration))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    func lightweightColumnValue(
        _ column: TrackTableColumn
    ) -> some View {
        switch column {
        case .album:
            Text(track.album)
                .lineLimit(1)
        case .year:
            Text(
                track.year?.formatted(.number.grouping(.never))
                    ?? "—"
            )
        case .time:
            Text(timeText(track.duration))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    var actions: some View {
        Button("Play", systemImage: "play.fill") {
            play()
        }
        .disabled(!ownsPlaylistContext)
        if let playlistID {
            Button(
                "Remove from Playlist",
                systemImage: "minus.circle"
            ) {
                Task {
                    await model.librarySession.store
                        .removeFromSelectedPlaylist(
                            playlistID: playlistID,
                            trackIDs: actionTrackIDs
                        )
                }
            }
            .disabled(!ownsPlaylistContext)
        }
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            guard ownsPlaylistContext else {
                return
            }
            model.playProductionNext(actionTrackIDs)
        }
        .disabled(!ownsPlaylistContext)
        Button("Add to Queue", systemImage: "text.badge.plus") {
            guard ownsPlaylistContext else {
                return
            }
            model.addToProductionQueue(actionTrackIDs)
        }
        .disabled(!ownsPlaylistContext)
        if actionTrackIDs.count == 1 {
            Button(
                track.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: track.isFavorite ? "heart.slash" : "heart"
            ) {
                Task {
                    await model.setProductionTrackFavorite(
                        track,
                        isFavorite: !track.isFavorite
                    )
                }
            }
            Button("Edit Tags…", systemImage: "tag.badge.plus") {
                model.openProductionTagEditor(trackID: track.id)
            }
        }
        QuickTrackTagMenuItems(
            store: model.librarySession.store,
            trackIDs: actionTrackIDs
        )
        AddToPlaylistMenuItems(
            model: model,
            store: model.librarySession.store,
            trackIDs: actionTrackIDs
        )
        if actionTrackIDs.count == 1 {
            ArtworkMenuItems(
                model: model,
                target: .managedTrack(track.id),
                label: "Track Artwork"
            )
        }
        Divider()
        Button(
            "Move to Trash…",
            systemImage: "trash",
            role: .destructive
        ) {
            model.requestLibraryDeletion(
                trackIDs: actionTrackIDs,
                title: actionTrackIDs.count == 1
                    ? track.title
                    : "\(actionTrackIDs.count) selected tracks"
            )
        }
    }

    func reorder(_ values: [String]) -> Bool {
        guard ownsPlaylistContext, let reorderAction else {
            return false
        }
        let sourceIDs = Set(
            values
                .flatMap { $0.split(separator: ",") }
                .compactMap { UUID(uuidString: String($0)) }
        )
        let movingIDs = resolveDraggedTrackIDs(sourceIDs)
        guard !movingIDs.isEmpty else {
            return false
        }
        reorderAction(
            queueIDProvider.reorderedIDs(
                moving: movingIDs,
                before: track.id
            )
        )
        return true
    }

    func timeText(
        _ duration: TimeInterval
    ) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func play() {
        guard ownsPlaylistContext else {
            return
        }
        model.playProductionTrack(
            track,
            withinTrackIDs: queueIDProvider.orderedIDs,
            source: queueSource
        )
    }

    var ownsPlaylistContext: Bool {
        let store = model.librarySession.store
        if let playlistID,
           !store.ownsSelectedPlaylistTracks(for: playlistID) {
            return false
        }
        if let queueSource,
           case let .playlist(queuePlaylistID) = queueSource {
            guard playlistID == nil || playlistID == queuePlaylistID else {
                return false
            }
            return store.ownsSelectedPlaylistTracks(
                for: queuePlaylistID
            )
        }
        return true
    }
}
