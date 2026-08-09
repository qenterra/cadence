import AppKit
import SwiftUI

struct NativeAllTracksTable: View {
    @Bindable var model: CadenceAppModel
    @Bindable var window: LibraryTrackWindow
    let repositorySortAction: (LibraryTrackSort) async -> Void
    @Binding var selection: Set<UUID>

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
        NativeTrackTableRepresentable(
            model: model,
            window: window,
            revision: window.revision,
            totalCount: window.totalCount,
            columns: visibleColumns,
            widths: widths,
            minimumWidth: minimumTableWidth,
            header: AnyView(header),
            selection: $selection
        )
        .task(id: repositorySort) {
            await repositorySortAction(repositorySort)
        }
    }
}

private extension NativeAllTracksTable {
    var header: some View {
        HStack(spacing: 14) {
            headerCell(
                field: .song,
                width: $songWidth,
                range: TrackTableWidth.song
            )

            ForEach(visibleColumns) { column in
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

    var visibleColumns: [TrackTableColumn] {
        TrackTableColumn.decode(visibleColumnsRaw)
    }

    var sortDescriptor: TrackTableSortDescriptor {
        TrackTableSortDescriptor(
            field: TrackTableSortField(rawValue: sortFieldRaw) ?? .song,
            direction: TrackTableSortDirection(rawValue: sortDirectionRaw)
                ?? .ascending
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

    var widths: TrackTableResolvedWidths {
        TrackTableResolvedWidths(
            song: songWidth,
            album: albumWidth,
            year: yearWidth,
            dateAdded: dateAddedWidth,
            playCount: playCountWidth,
            time: timeWidth
        )
    }

    var minimumTableWidth: CGFloat {
        let columnWidth = visibleColumns.reduce(0.0) {
            $0 + widths[$1]
        }
        let itemCount = visibleColumns.count + 3
        let spacing = Double(max(itemCount - 1, 0)) * 14
        return CGFloat(songWidth + columnWidth + spacing + 28 + 24)
    }

    func headerCell(
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

    func sortField(for column: TrackTableColumn) -> TrackTableSortField {
        switch column {
        case .album: .album
        case .year: .year
        case .dateAdded: .dateAdded
        case .playCount: .playCount
        case .time: .time
        }
    }

    func widthBinding(for column: TrackTableColumn) -> Binding<Double> {
        switch column {
        case .album: $albumWidth
        case .year: $yearWidth
        case .dateAdded: $dateAddedWidth
        case .playCount: $playCountWidth
        case .time: $timeWidth
        }
    }

    func widthRange(for column: TrackTableColumn) -> TrackTableWidthRange {
        switch column {
        case .album: TrackTableWidth.album
        case .year: TrackTableWidth.year
        case .dateAdded: TrackTableWidth.dateAdded
        case .playCount: TrackTableWidth.playCount
        case .time: TrackTableWidth.time
        }
    }
}

private struct NativeTrackTableRepresentable: NSViewRepresentable {
    let model: CadenceAppModel
    let window: LibraryTrackWindow
    let revision: Int
    let totalCount: Int
    let columns: [TrackTableColumn]
    let widths: TrackTableResolvedWidths
    let minimumWidth: CGFloat
    let header: AnyView
    @Binding var selection: Set<UUID>

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 58
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.playSelectedRow)

        let column = NSTableColumn(identifier: Coordinator.columnIdentifier)
        column.resizingMask = []
        column.minWidth = minimumWidth
        column.width = minimumWidth
        tableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.attach(
            tableView: tableView,
            scrollView: scrollView
        )
        return scrollView
    }

    func updateNSView(
        _ scrollView: NSScrollView,
        context: Context
    ) {
        let coordinator = context.coordinator
        let previousCount = coordinator.parent.totalCount
        let previousRevision = coordinator.parent.revision
        let previousMinimumWidth = coordinator.parent.minimumWidth
        coordinator.parent = self

        guard let tableView = scrollView.documentView as? NSTableView else {
            return
        }
        coordinator.updateColumnWidth()
        if previousCount != totalCount {
            tableView.noteNumberOfRowsChanged()
        }
        if previousRevision != revision
            || previousMinimumWidth != minimumWidth {
            coordinator.reloadVisibleRows()
        }
        coordinator.restoreSelectionIfPossible()
        coordinator.requestVisibleRows()
    }

    static func dismantleNSView(
        _: NSScrollView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let columnIdentifier = NSUserInterfaceItemIdentifier(
            "Cadence.NativeTrackRow"
        )
        static let cellIdentifier = NSUserInterfaceItemIdentifier(
            "Cadence.NativeTrackHostingCell"
        )

        var parent: NativeTrackTableRepresentable
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        private var pendingPages: [Int: Task<Void, Never>] = [:]
        private var previousVisibleTrackRow: Int?

        init(parent: NativeTrackTableRepresentable) {
            self.parent = parent
        }

        func attach(
            tableView: NSTableView,
            scrollView: NSScrollView
        ) {
            self.tableView = tableView
            self.scrollView = scrollView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(visibleBoundsChanged),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            pendingPages.values.forEach { $0.cancel() }
            pendingPages.removeAll()
        }

        func numberOfRows(in _: NSTableView) -> Int {
            parent.totalCount + 1
        }

        func tableView(
            _: NSTableView,
            heightOfRow row: Int
        ) -> CGFloat {
            row == 0 ? 38 : 58
        }

        func tableView(
            _: NSTableView,
            shouldSelectRow row: Int
        ) -> Bool {
            row > 0
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor _: NSTableColumn?,
            row: Int
        ) -> NSView? {
            let cell = hostingCell(in: tableView)
            if row == 0 {
                cell.setRootView(parent.header)
                return cell
            }

            let trackIndex = row - 1
            if let track = parent.window.track(at: trackIndex) {
                let isSelected = parent.selection.contains(track.id)
                cell.setRootView(
                    AnyView(
                        ProductionTrackTableRow(
                            model: parent.model,
                            track: track,
                            queue: [track],
                            columns: parent.columns,
                            widths: parent.widths,
                            playlistID: nil,
                            queueSource: .allTracks,
                            reorderAction: nil,
                            isSelected: isSelected,
                            isFocused: isSelected
                                && tableView.window?.firstResponder
                                === tableView,
                            select: { [weak self] in
                                self?.select(trackID: track.id, row: row)
                            }
                        )
                    )
                )
            } else {
                cell.setRootView(AnyView(NativeTrackPlaceholderRow()))
                request(
                    page: trackIndex / parent.window.pageSize,
                    direction: .none
                )
            }
            return cell
        }

        func tableViewSelectionDidChange(_: Notification) {
            guard let tableView else {
                return
            }
            let row = tableView.selectedRow
            guard row > 0,
                  let track = parent.window.track(at: row - 1)
            else {
                parent.selection = []
                return
            }
            parent.selection = [track.id]
            reloadVisibleRows()
        }

        @objc func playSelectedRow() {
            guard let tableView else {
                return
            }
            let row = tableView.clickedRow >= 0
                ? tableView.clickedRow
                : tableView.selectedRow
            guard row > 0,
                  let track = parent.window.track(at: row - 1)
            else {
                return
            }
            parent.model.playProductionTrack(
                track,
                within: [track],
                source: .allTracks
            )
        }

        @objc func visibleBoundsChanged() {
            updateColumnWidth()
            requestVisibleRows()
        }

        func requestVisibleRows() {
            guard let tableView, parent.totalCount > 0 else {
                return
            }
            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.length > 0 else {
                return
            }
            let firstTrackRow = max(visible.location - 1, 0)
            let lastTableRow = visible.location + visible.length - 1
            let lastTrackRow = min(lastTableRow - 1, parent.totalCount - 1)
            guard firstTrackRow <= lastTrackRow else {
                return
            }

            let direction: TrackViewportPrefetchDirection = if let previousVisibleTrackRow {
                if firstTrackRow < previousVisibleTrackRow {
                    .before
                } else if firstTrackRow > previousVisibleTrackRow {
                    .after
                } else {
                    .none
                }
            } else {
                .after
            }
            previousVisibleTrackRow = firstTrackRow

            let firstPage = firstTrackRow / parent.window.pageSize
            let lastPage = lastTrackRow / parent.window.pageSize
            request(page: firstPage, direction: direction)
            if lastPage != firstPage {
                request(page: lastPage, direction: direction)
            }
        }

        func reloadVisibleRows() {
            guard let tableView else {
                return
            }
            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.length > 0 else {
                return
            }
            tableView.reloadData(
                forRowIndexes: IndexSet(integersIn: visible.location ..< (
                    visible.location + visible.length
                )),
                columnIndexes: IndexSet(integer: 0)
            )
        }

        func restoreSelectionIfPossible() {
            guard
                let tableView,
                tableView.selectedRow < 1,
                let selectedID = parent.selection.first,
                let index = parent.window.index(ofTrackID: selectedID)
            else {
                return
            }
            tableView.selectRowIndexes(
                IndexSet(integer: index + 1),
                byExtendingSelection: false
            )
        }

        func updateColumnWidth() {
            guard
                let tableView,
                let scrollView,
                let column = tableView.tableColumns.first
            else {
                return
            }
            let width = max(parent.minimumWidth, scrollView.contentSize.width)
            if abs(column.width - width) > 0.5 {
                column.minWidth = parent.minimumWidth
                column.width = width
            }
        }

        private func select(trackID: UUID, row: Int) {
            parent.selection = [trackID]
            tableView?.selectRowIndexes(
                IndexSet(integer: row),
                byExtendingSelection: false
            )
        }

        private func request(
            page: Int,
            direction: TrackViewportPrefetchDirection
        ) {
            guard pendingPages[page] == nil else {
                return
            }
            pendingPages[page] = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                await parent.window.load(
                    page: page,
                    prefetchDirection: direction
                )
                pendingPages[page] = nil
            }
        }

        private func hostingCell(
            in tableView: NSTableView
        ) -> NativeTrackHostingCell {
            if let reused = tableView.makeView(
                withIdentifier: Self.cellIdentifier,
                owner: nil
            ) as? NativeTrackHostingCell {
                return reused
            }
            let cell = NativeTrackHostingCell()
            cell.identifier = Self.cellIdentifier
            return cell
        }
    }
}

@MainActor
private final class NativeTrackHostingCell: NSTableCellView {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func setRootView(_ rootView: AnyView) {
        hostingView.rootView = rootView
    }
}

private struct NativeTrackPlaceholderRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: CadenceTheme.radiusControl, style: .continuous)
                .fill(CadenceTheme.subduedFill)
                .frame(width: 40, height: 40)
            RoundedRectangle(cornerRadius: CadenceTheme.radiusControl, style: .continuous)
                .fill(CadenceTheme.subduedFill)
                .frame(width: 180, height: 12)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
                .padding(.leading, 54)
        }
        .accessibilityHidden(true)
    }
}
