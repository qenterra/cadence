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
    var scrollAxes: Axis.Set = .horizontal
    var virtualWindow: LibraryTrackWindow?
    var repositorySortAction: ((LibraryTrackSort) async -> Void)?
    var selection: Binding<Set<UUID>>?

    @State private var localSelection: Set<UUID> = []
    @State private var isRequestingNextPage = false
    @FocusState private var tableHasFocus: Bool

    @AppStorage("trackTable.visibleColumns")
    private var visibleColumnsRaw = TrackTableColumn.defaultRawValue
    @AppStorage("trackTable.sortField")
    private var sortFieldRaw = TrackTableSortField.song.rawValue
    @AppStorage("trackTable.sortDirection")
    private var sortDirectionRaw = TrackTableSortDirection.ascending.rawValue
    @AppStorage("trackTable.songWidth")
    private var songWidth = TrackTableWidth.song.defaultValue
    @AppStorage("trackTable.albumWidth")
    private var albumWidth = TrackTableWidth.album.defaultValue
    @AppStorage("trackTable.yearWidth")
    private var yearWidth = TrackTableWidth.year.defaultValue
    @AppStorage("trackTable.dateAddedWidth")
    private var dateAddedWidth = TrackTableWidth.dateAdded.defaultValue
    @AppStorage("trackTable.playCountWidth")
    private var playCountWidth = TrackTableWidth.playCount.defaultValue
    @AppStorage("trackTable.timeWidth")
    private var timeWidth = TrackTableWidth.time.defaultValue

    var body: some View {
        let renderedTracks = displayedTracks

        ScrollView(scrollAxes) {
            LazyVStack(spacing: 0) {
                if showsHeader {
                    header
                }

                if let virtualWindow {
                    ForEach(0 ..< virtualWindow.pageCount, id: \.self) { page in
                        VirtualTrackTablePage(
                            model: model,
                            window: virtualWindow,
                            page: page,
                            columns: displayedColumns,
                            widths: widths,
                            playlistID: playlistID,
                            queueSource: queueSource,
                            selection: selectedTrackIDs,
                            tableHasFocus: tableHasFocus,
                            select: { trackID in
                                selectedTrackIDs.wrappedValue = [trackID]
                                tableHasFocus = true
                            }
                        )
                    }
                } else {
                    ForEach(renderedTracks) { track in
                        ProductionTrackTableRow(
                            model: model,
                            track: track,
                            queue: renderedTracks,
                            columns: displayedColumns,
                            widths: widths,
                            playlistID: playlistID,
                            queueSource: queueSource,
                            reorderAction: reorderAction,
                            isSelected: selectedTrackIDs.wrappedValue.contains(
                                track.id
                            ),
                            isFocused: tableHasFocus
                                && selectedTrackIDs.wrappedValue.contains(
                                    track.id
                                ),
                            select: {
                                selectedTrackIDs.wrappedValue = [track.id]
                                tableHasFocus = true
                            }
                        )
                    }
                }

                if virtualWindow == nil, onReachEnd != nil {
                    Color.clear
                        .frame(height: 1)
                        .onScrollVisibilityChange(
                            threshold: 0.5,
                            handleEndVisibility
                        )
                }
            }
            .frame(minWidth: minimumTableWidth, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.leading)
        .task(id: repositorySort) {
            await repositorySortAction?(repositorySort)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($tableHasFocus)
        .onKeyPress(.return, phases: .down) { _ in
            playSelectedTrack() ? .handled : .ignored
        }
        .onKeyPress(.upArrow, phases: .down) { _ in
            moveSelection(by: -1) ? .handled : .ignored
        }
        .onKeyPress(.downArrow, phases: .down) { _ in
            moveSelection(by: 1) ? .handled : .ignored
        }
        .onChange(of: renderedTracks.map(\.id), initial: true) {
            guard virtualWindow == nil else {
                return
            }
            selectedTrackIDs.wrappedValue.formIntersection(
                renderedTracks.map(\.id)
            )
        }
    }
}

private extension ProductionTrackTable {
    private func handleEndVisibility(
        _ isVisible: Bool
    ) {
        guard isVisible, !isRequestingNextPage else {
            return
        }
        isRequestingNextPage = true
        Task {
            await onReachEnd?()
            isRequestingNextPage = false
        }
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
        .guideAnchor(.trackTable)
    }

    private var visibleColumns: [TrackTableColumn] {
        TrackTableColumn.decode(visibleColumnsRaw)
    }

    private var displayedColumns: [TrackTableColumn] {
        compact ? [] : visibleColumns
    }

    private var displayedTracks: [LibraryTrackProjection] {
        guard repositorySortAction == nil else {
            return tracks
        }
        return sortDescriptor.sorted(tracks)
    }

    private var selectedTrackIDs: Binding<Set<UUID>> {
        selection ?? $localSelection
    }

    private func playSelectedTrack() -> Bool {
        let selectedIDs = selectedTrackIDs.wrappedValue
        let track = virtualWindow.flatMap { window in
            selectedIDs.lazy.compactMap(window.cachedTrack).first
        } ?? displayedTracks.first(where: {
            selectedIDs.contains($0.id)
        })
        guard let track else {
            return false
        }
        model.playProductionTrack(
            track,
            within: virtualWindow == nil ? displayedTracks : [track],
            source: queueSource ?? .adHoc
        )
        return true
    }

    private func moveSelection(by offset: Int) -> Bool {
        if let virtualWindow {
            guard virtualWindow.totalCount > 0 else {
                return false
            }
            let selectedID = selectedTrackIDs.wrappedValue.first
            let selectedIndex = selectedID.flatMap(
                virtualWindow.index(ofTrackID:)
            ) ?? (offset > 0 ? -1 : virtualWindow.totalCount)
            let targetIndex = min(
                max(selectedIndex + offset, 0),
                virtualWindow.totalCount - 1
            )
            if let target = virtualWindow.track(at: targetIndex) {
                selectedTrackIDs.wrappedValue = [target.id]
            } else {
                Task {
                    await virtualWindow.load(
                        page: targetIndex / virtualWindow.pageSize
                    )
                    if let target = virtualWindow.track(at: targetIndex) {
                        selectedTrackIDs.wrappedValue = [target.id]
                    }
                }
            }
            return true
        }
        guard !displayedTracks.isEmpty else {
            return false
        }
        let selectedIndex = displayedTracks.firstIndex {
            selectedTrackIDs.wrappedValue.contains($0.id)
        } ?? (offset > 0 ? -1 : displayedTracks.count)
        let targetIndex = min(
            max(selectedIndex + offset, 0),
            displayedTracks.count - 1
        )
        selectedTrackIDs.wrappedValue = [displayedTracks[targetIndex].id]
        return true
    }

    private var repositorySort: LibraryTrackSort {
        let field: LibraryTrackSortField = switch sortDescriptor.field {
        case .song: .song
        case .album: .album
        case .year: .year
        case .dateAdded: .dateAdded
        case .playCount: .playCount
        case .time: .duration
        }
        return LibraryTrackSort(
            field: field,
            direction: sortDescriptor.direction == .ascending
                ? .ascending
                : .descending
        )
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
        range: TrackTableWidthRange
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
    ) -> TrackTableWidthRange {
        switch column {
        case .album: TrackTableWidth.album
        case .year: TrackTableWidth.year
        case .dateAdded: TrackTableWidth.dateAdded
        case .playCount: TrackTableWidth.playCount
        case .time: TrackTableWidth.time
        }
    }
}
