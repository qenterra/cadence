import SwiftUI

struct SmartCollectionTrackTable: View {
    @Bindable var model: CadenceAppModel

    @AppStorage("trackTable.visibleColumns")
    private var visibleColumnsRaw = TrackTableColumn.defaultRawValue
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
        ScrollView {
            ScrollView(.horizontal) {
                LazyVStack(spacing: 0) {
                    header

                    ForEach(
                        model.selectedSmartCollectionVisibleTracks
                    ) { track in
                        SmartCollectionTrackTableRow(
                            model: model,
                            track: track,
                            columns: visibleColumns,
                            widths: widths
                        )
                    }
                }
                .frame(minWidth: minimumTableWidth, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            headerCell(
                title: "Song",
                field: .title,
                width: $songWidth,
                range: TrackTableWidth.song,
                alignment: .leading
            )

            ForEach(visibleColumns) { column in
                headerCell(
                    title: column.title,
                    field: sortField(for: column),
                    width: widthBinding(for: column),
                    range: widthRange(for: column),
                    alignment: column == .album ? .leading : .trailing
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
    }

    private func headerCell(
        title: String,
        field: SmartCollectionSortField,
        width: Binding<Double>,
        range: TrackTableWidthRange,
        alignment: Alignment
    ) -> some View {
        let descriptor = model.selectedSmartCollectionSortDescriptor
        let isActive = descriptor.field == field

        return TrackTableHeaderCell(
            title: title,
            alignment: alignment,
            isSorted: isActive,
            direction: descriptor.direction == .ascending
                ? .ascending
                : .descending,
            minimumWidth: range.minimum,
            maximumWidth: range.maximum,
            width: width,
            sortAction: {
                model.activateSelectedSmartCollectionSort(field)
            }
        )
    }

    private var visibleColumns: [TrackTableColumn] {
        TrackTableColumn.decode(visibleColumnsRaw)
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
    ) -> SmartCollectionSortField {
        switch column {
        case .album: .album
        case .year: .year
        case .dateAdded: .dateAdded
        case .playCount: .playCount
        case .time: .duration
        }
    }

    private var widths: SmartCollectionTrackTableWidths {
        SmartCollectionTrackTableWidths(
            song: songWidth,
            album: albumWidth,
            year: yearWidth,
            dateAdded: dateAddedWidth,
            playCount: playCountWidth,
            time: timeWidth
        )
    }

    private var minimumTableWidth: CGFloat {
        let columnWidth = visibleColumns.reduce(0.0) {
            $0 + widths[$1]
        }
        let itemCount = visibleColumns.count + 3
        let spacing = Double(max(itemCount - 1, 0)) * 14
        return CGFloat(songWidth + columnWidth + spacing + 28 + 24)
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

struct SmartCollectionTrackTableWidths {
    let song: CGFloat
    let album: CGFloat
    let year: CGFloat
    let dateAdded: CGFloat
    let playCount: CGFloat
    let time: CGFloat

    init(
        song: Double,
        album: Double,
        year: Double,
        dateAdded: Double,
        playCount: Double,
        time: Double
    ) {
        self.song = CGFloat(song)
        self.album = CGFloat(album)
        self.year = CGFloat(year)
        self.dateAdded = CGFloat(dateAdded)
        self.playCount = CGFloat(playCount)
        self.time = CGFloat(time)
    }

    subscript(column: TrackTableColumn) -> CGFloat {
        switch column {
        case .album: album
        case .year: year
        case .dateAdded: dateAdded
        case .playCount: playCount
        case .time: time
        }
    }
}
