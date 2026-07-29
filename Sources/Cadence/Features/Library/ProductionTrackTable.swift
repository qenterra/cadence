import SwiftUI

struct ProductionTrackTable: View {
    @Bindable var model: CadenceAppModel
    let tracks: [LibraryTrackProjection]
    var showsHeader = true
    var compact = false
    var playlistID: UUID?
    var queueSource: PlaybackQueueSource?
    var reorderAction: (([UUID]) -> Void)?
    var onReachEnd: (() async -> Void)?

    @AppStorage("trackTable.visibleColumns")
    private var visibleColumnsRaw = TrackTableColumn.defaultRawValue
    @AppStorage("trackTable.sortField")
    private var sortFieldRaw = TrackTableSortField.song.rawValue
    @AppStorage("trackTable.sortDirection")
    private var sortDirectionRaw = TrackTableSortDirection.ascending.rawValue
    @AppStorage("trackTable.songWidth")
    private var songWidth = TrackTableWidth.song.default
    @AppStorage("trackTable.albumWidth")
    private var albumWidth = TrackTableWidth.album.default
    @AppStorage("trackTable.yearWidth")
    private var yearWidth = TrackTableWidth.year.default
    @AppStorage("trackTable.dateAddedWidth")
    private var dateAddedWidth = TrackTableWidth.dateAdded.default
    @AppStorage("trackTable.playCountWidth")
    private var playCountWidth = TrackTableWidth.playCount.default
    @AppStorage("trackTable.timeWidth")
    private var timeWidth = TrackTableWidth.time.default

    var body: some View {
        ScrollView(.horizontal) {
            LazyVStack(spacing: 0) {
                if showsHeader {
                    header
                }

                ForEach(displayedTracks) { track in
                    ProductionTrackTableRow(
                        model: model,
                        track: track,
                        queue: displayedTracks,
                        columns: displayedColumns,
                        widths: widths,
                        playlistID: playlistID,
                        queueSource: queueSource,
                        reorderAction: reorderAction
                    )
                    .task {
                        guard track.id == displayedTracks.last?.id else {
                            return
                        }
                        await onReachEnd?()
                    }
                }
            }
            .frame(minWidth: minimumTableWidth, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(spacing: 14) {
            headerCell(
                field: .song,
                width: $songWidth,
                range: TrackTableWidth.song
            )

            ForEach(displayedColumns) { column in
                headerCell(
                    field: sortField(for: column),
                    width: widthBinding(for: column),
                    range: widthRange(for: column)
                )
            }

            Spacer(minLength: 0)

            Menu {
                Text("Columns")
                ForEach(TrackTableColumn.allCases) { column in
                    Toggle(
                        column.title,
                        isOn: visibilityBinding(for: column)
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .help("Choose Columns")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
        }
        .contextMenu {
            ForEach(TrackTableColumn.allCases) { column in
                Toggle(
                    column.title,
                    isOn: visibilityBinding(for: column)
                )
            }
        }
    }

    private var visibleColumns: [TrackTableColumn] {
        TrackTableColumn.decode(visibleColumnsRaw)
    }

    private var displayedColumns: [TrackTableColumn] {
        compact ? [] : visibleColumns
    }

    private var displayedTracks: [LibraryTrackProjection] {
        sortDescriptor.sorted(tracks)
    }

    private var sortDescriptor: TrackTableSortDescriptor {
        TrackTableSortDescriptor(
            field: TrackTableSortField(rawValue: sortFieldRaw) ?? .song,
            direction: TrackTableSortDirection(
                rawValue: sortDirectionRaw
            ) ?? .ascending
        )
    }

    private var widths: TrackTableResolvedWidths {
        TrackTableResolvedWidths(
            song: songWidth,
            album: albumWidth,
            year: yearWidth,
            dateAdded: dateAddedWidth,
            playCount: playCountWidth,
            time: timeWidth
        )
    }

    private var minimumTableWidth: CGFloat {
        let columnWidth = displayedColumns.reduce(0.0) {
            $0 + widths[$1]
        }
        let itemCount = displayedColumns.count + 3
        let spacing = Double(max(itemCount - 1, 0)) * 14
        return CGFloat(
            songWidth + columnWidth + spacing + 28 + 24
        )
    }

    private func headerCell(
        field: TrackTableSortField,
        width: Binding<Double>,
        range: (
            minimum: Double,
            default: Double,
            maximum: Double
        )
    ) -> some View {
        TrackTableHeaderCell(
            title: field.title,
            alignment: field == .song || field == .album
                ? .leading
                : .trailing,
            isSorted: sortDescriptor.field == field,
            direction: sortDescriptor.direction,
            minimumWidth: range.minimum,
            maximumWidth: range.maximum,
            width: width,
            sortAction: {
                activateSort(field)
            }
        )
    }

    private func activateSort(
        _ field: TrackTableSortField
    ) {
        var direction = sortDescriptor.direction
        if sortDescriptor.field == field {
            direction.toggle()
        } else {
            direction = .ascending
        }
        sortFieldRaw = field.rawValue
        sortDirectionRaw = direction.rawValue
    }

    private func visibilityBinding(
        for column: TrackTableColumn
    ) -> Binding<Bool> {
        Binding(
            get: { visibleColumns.contains(column) },
            set: { isVisible in
                var columns = Set(visibleColumns)
                if isVisible {
                    columns.insert(column)
                } else {
                    columns.remove(column)
                }
                visibleColumnsRaw = TrackTableColumn.encode(columns)
            }
        )
    }

    private func sortField(
        for column: TrackTableColumn
    ) -> TrackTableSortField {
        switch column {
        case .album: .album
        case .year: .year
        case .dateAdded: .dateAdded
        case .playCount: .playCount
        case .time: .time
        }
    }

    private func widthBinding(
        for column: TrackTableColumn
    ) -> Binding<Double> {
        switch column {
        case .album: $albumWidth
        case .year: $yearWidth
        case .dateAdded: $dateAddedWidth
        case .playCount: $playCountWidth
        case .time: $timeWidth
        }
    }

    private func widthRange(
        for column: TrackTableColumn
    ) -> (
        minimum: Double,
        default: Double,
        maximum: Double
    ) {
        switch column {
        case .album: TrackTableWidth.album
        case .year: TrackTableWidth.year
        case .dateAdded: TrackTableWidth.dateAdded
        case .playCount: TrackTableWidth.playCount
        case .time: TrackTableWidth.time
        }
    }
}

private struct TrackTableResolvedWidths {
    let song: Double
    let album: Double
    let year: Double
    let dateAdded: Double
    let playCount: Double
    let time: Double

    subscript(column: TrackTableColumn) -> Double {
        switch column {
        case .album: album
        case .year: year
        case .dateAdded: dateAdded
        case .playCount: playCount
        case .time: time
        }
    }
}

private struct ProductionTrackTableRow: View {
    @Bindable var model: CadenceAppModel
    let track: LibraryTrackProjection
    let queue: [LibraryTrackProjection]
    let columns: [TrackTableColumn]
    let widths: TrackTableResolvedWidths
    let playlistID: UUID?
    let queueSource: PlaybackQueueSource?
    let reorderAction: (([UUID]) -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
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
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .help("Track Actions")
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background {
            if isHovered {
                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
                .fill(CadenceTheme.hoverFill)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            play()
        }
        .contextMenu {
            actions
        }
        .draggable(track.id.uuidString)
        .dropDestination(for: String.self) { values, _ in
            guard let reorderAction else {
                return false
            }
            let movingIDs = Set(values.compactMap(UUID.init(uuidString:)))
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
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
                .padding(.leading, 54)
        }
    }

    private var song: some View {
        HStack(spacing: 10) {
            Button {
                play()
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
                    if model.isCurrentProductionTrack(track.id) {
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

                    Text(track.codec.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(
                            CadenceTheme.subduedFill,
                            in: Capsule()
                        )
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
        case .dateAdded:
            Text(
                track.dateAdded.formatted(
                    .dateTime.year().month(.abbreviated).day()
                )
            )
            .lineLimit(1)
        case .playCount:
            Text(track.playCount.formatted())
                .monospacedDigit()
        case .time:
            Text(timeText(track.duration))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var actions: some View {
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
                        .removeFromSelectedPlaylist(trackIDs: [track.id])
                }
            }
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

    private func timeText(
        _ duration: TimeInterval
    ) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func play() {
        model.playProductionTrack(
            track,
            within: queue,
            source: queueSource
        )
    }
}
