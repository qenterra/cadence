import SwiftUI

struct ProductionTrackTable: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Bindable var model: CadenceAppModel
    let tracks: [LibraryTrackProjection]
    var context: TrackTableContext = .library
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
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width, 1)
            let useCompactLayout = compact
                || TrackTableColumnPolicy.mode(
                    availableWidth: availableWidth
                ) == .compact
            let columns = useCompactLayout ? [] : visibleColumns
            let contentWidth = TrackTableColumnPolicy.contentWidth(
                availableWidth: availableWidth,
                columns: columns
            )
            let resolvedWidths = TrackTableColumnPolicy.layout(
                availableWidth: contentWidth,
                columns: columns,
                preferred: preferredWidths
            )

            VStack(spacing: 0) {
                if showsHeader {
                    header(
                        columns: columns,
                        widths: resolvedWidths
                    )
                    .transition(.opacity)
                }

                TrackTableCore(
                    model: model,
                    context: context,
                    tracks: displayedTracks,
                    virtualWindow: virtualWindow,
                    columns: columns,
                    widths: resolvedWidths,
                    playlistID: playlistID,
                    queueSource: queueSource,
                    reorderAction: reorderAction,
                    onReachEnd: onReachEnd,
                    selection: selectedTrackIDs
                )
            }
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: CadenceTheme.motionReplace),
                value: useCompactLayout
            )
        }
        .task(id: repositorySort) {
            await repositorySortAction?(repositorySort)
        }
        .onChange(of: displayedTracks.map(\.id), initial: true) {
            guard virtualWindow == nil else {
                return
            }
            selectedTrackIDs.wrappedValue.formIntersection(
                displayedTracks.map(\.id)
            )
        }
        .onChange(of: context) {
            selectedTrackIDs.wrappedValue = []
        }
    }
}

private extension ProductionTrackTable {
    var visibleColumns: [TrackTableColumn] {
        TrackTableColumn.decode(visibleColumnsRaw)
    }

    var displayedTracks: [LibraryTrackProjection] {
        guard repositorySortAction == nil else {
            return tracks
        }
        return sortDescriptor.sorted(tracks)
    }

    var selectedTrackIDs: Binding<Set<UUID>> {
        selection ?? $localSelection
    }

    var preferredWidths: TrackTableResolvedWidths {
        TrackTableResolvedWidths(
            song: songWidth,
            album: albumWidth,
            year: yearWidth,
            dateAdded: dateAddedWidth,
            playCount: playCountWidth,
            time: timeWidth
        )
    }

    var repositorySort: LibraryTrackSort {
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

    var sortDescriptor: TrackTableSortDescriptor {
        TrackTableSortDescriptor(
            field: TrackTableSortField(rawValue: sortFieldRaw) ?? .song,
            direction: TrackTableSortDirection(
                rawValue: sortDirectionRaw
            ) ?? .ascending
        )
    }

    func header(
        columns: [TrackTableColumn],
        widths: TrackTableResolvedWidths
    ) -> some View {
        HStack(spacing: 14) {
            headerCell(
                field: .song,
                resolvedWidth: widths.song,
                preferredWidth: $songWidth,
                range: TrackTableWidth.song
            )

            ForEach(columns) { column in
                headerCell(
                    field: sortField(for: column),
                    resolvedWidth: widths[column],
                    preferredWidth: widthBinding(for: column),
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

    func headerCell(
        field: TrackTableSortField,
        resolvedWidth: Double,
        preferredWidth: Binding<Double>,
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
            resolvedWidth: resolvedWidth,
            preferredWidth: preferredWidth,
            sortAction: { activateSort(field) }
        )
    }

    func activateSort(_ field: TrackTableSortField) {
        var direction = sortDescriptor.direction
        if sortDescriptor.field == field {
            direction.toggle()
        } else {
            direction = .ascending
        }
        sortFieldRaw = field.rawValue
        sortDirectionRaw = direction.rawValue
    }

    func visibilityBinding(
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

    func sortField(
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

    func widthBinding(
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

    func widthRange(
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
