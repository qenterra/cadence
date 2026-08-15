import SwiftUI

struct TrackTableResolvedWidths: Equatable, Sendable {
    let song: Double
    let album: Double
    let year: Double
    let time: Double

    subscript(column: TrackTableColumn) -> Double {
        switch column {
        case .album: album
        case .year: year
        case .time: time
        }
    }
}

struct ProductionTrackTableRow: View {
    @Bindable var model: CadenceAppModel
    let track: LibraryTrackProjection
    let queue: [LibraryTrackProjection]
    let columns: [TrackTableColumn]
    let widths: TrackTableResolvedWidths
    let playlistID: UUID?
    let queueSource: PlaybackQueueSource?
    let reorderAction: (([UUID]) -> Void)?
    let actionTrackIDs: [UUID]
    let isSelected: Bool
    let isFocused: Bool
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: TrackTableColumnPolicy.columnSpacing) {
            song
                .frame(width: CGFloat(widths.song), alignment: .leading)

            ForEach(columns) { column in
                columnValue(column)
                    .frame(
                        width: CGFloat(widths[column]),
                        alignment: column == .album ? .leading : .trailing
                    )
            }

            Spacer(minLength: 0)

            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(isHovered ? .primary : .tertiary)
                    .frame(
                        width: TrackTableColumnPolicy.actionWidth,
                        height: TrackTableColumnPolicy.actionWidth
                    )
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .help("Track Actions")
        }
        .padding(.horizontal, TrackTableColumnPolicy.horizontalInset)
        .frame(height: 58)
        .background {
            BrowserRowSurface(
                isSelected: isSelected,
                isHovered: isHovered,
                isFocused: isFocused
            )
            .padding(.vertical, 3)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 1, perform: select)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            actions
        }
        .draggable(
            actionTrackIDs.map(\.uuidString).joined(separator: ",")
        )
        .dropDestination(for: String.self) { values, _ in
            _ = reorder(values)
        }
    }

    private var song: some View {
        HStack(spacing: TrackTableColumnPolicy.songContentSpacing) {
            FavoriteButton(
                isFavorite: track.isFavorite,
                itemName: track.title,
                controlSize: TrackTableColumnPolicy.favoriteControlWidth
            ) { requestedValue in
                await model.setProductionTrackFavorite(
                    track,
                    isFavorite: requestedValue
                ) != nil
            }
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .accessibilityHidden(!isHovered)
            .animation(
                .easeOut(duration: CadenceTheme.motionHover),
                value: isHovered
            )

            Button {
                play()
            } label: {
                artwork
            }
            .buttonStyle(.plain)
            .help("Play \(track.title)")

            songMetadata

            Spacer(minLength: 0)
        }
    }

    private var artwork: some View {
        ProductionArtworkView(
            model: model,
            artworkID: track.artworkID,
            title: track.title,
            placeholder: .track,
            variant: .trackRow,
            cornerRadius: CadenceTheme.radiusControl
        )
        .frame(width: 40, height: 40)
        .overlay {
            if isHovered || model.isCurrentProductionTrack(track.id) {
                let isPlayingCurrentTrack = model.isCurrentProductionTrack(track.id)
                    && model.isCurrentProductionTrackPlaying
                RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusControl,
                    style: .continuous
                )
                .fill(.black.opacity(0.34))
                Image(
                    systemName: Self.artworkOverlaySymbolName(
                        isCurrentTrack: model.isCurrentProductionTrack(track.id),
                        isPlaying: model.isCurrentProductionTrackPlaying
                    )
                )
                .contentTransition(.symbolEffect(.replace))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .symbolEffect(
                    .variableColor.iterative,
                    options: .repeating,
                    isActive: isPlayingCurrentTrack
                )
            }
        }
    }

    private var songMetadata: some View {
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

                Text(Self.formatPillTitle(track.codec))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(
                        CadenceTheme.subduedFill,
                        in: Capsule()
                    )

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

                if track.hasSynchronizedLyrics {
                    Text("LRC")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(
                            CadenceTheme.subduedFill,
                            in: Capsule()
                        )
                        .accessibilityLabel("Synchronized lyrics")
                }
            }

            Button {
                guard let artistID = track.artistID else {
                    return
                }
                model.requestOpenProductionArtistContextually(
                    id: artistID
                )
            } label: {
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(track.artistID == nil)
        }
    }

    @ViewBuilder
    private func columnValue(
        _ column: TrackTableColumn
    ) -> some View {
        switch column {
        case .album:
            Button {
                guard let albumID = track.albumID else {
                    return
                }
                model.requestOpenProductionAlbumContextually(id: albumID)
            } label: {
                Text(track.album)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
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
}

extension ProductionTrackTableRow {
    static func formatPillTitle(_ codec: String) -> String {
        codec
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "." })
            .uppercased()
    }

    static func artworkOverlaySymbolName(
        isCurrentTrack: Bool,
        isPlaying: Bool
    ) -> String {
        isCurrentTrack && isPlaying ? "waveform" : "play.fill"
    }
}

private extension ProductionTrackTableRow {
    @ViewBuilder
    var actions: some View {
        Button("Play", systemImage: "play.fill") {
            play()
        }
        if playlistID != nil {
            Button(
                "Remove from Playlist",
                systemImage: "minus.circle"
            ) {
                Task {
                    await model.librarySession.store
                        .removeFromSelectedPlaylist(trackIDs: actionTrackIDs)
                }
            }
        }
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            model.playProductionNext(actionTrackIDs)
        }
        Button("Add to Queue", systemImage: "text.badge.plus") {
            model.addToProductionQueue(actionTrackIDs)
        }
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
        guard let reorderAction else {
            return false
        }
        let movingIDs = Set(
            values
                .flatMap { $0.split(separator: ",") }
                .compactMap { UUID(uuidString: String($0)) }
        )
        guard !movingIDs.isEmpty else {
            return false
        }
        var orderedIDs = queue.map(\.id).filter {
            !movingIDs.contains($0)
        }
        let targetIndex = orderedIDs.firstIndex(of: track.id)
            ?? orderedIDs.endIndex
        orderedIDs.insert(
            contentsOf: queue.map(\.id).filter(movingIDs.contains),
            at: targetIndex
        )
        reorderAction(orderedIDs)
        return true
    }

    func timeText(
        _ duration: TimeInterval
    ) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func play() {
        model.playProductionTrack(
            track,
            within: queue,
            source: queueSource
        )
    }
}
