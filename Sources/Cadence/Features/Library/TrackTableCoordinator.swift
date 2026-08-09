import AppKit
import SwiftUI

extension TrackTableCore {
    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let columnIdentifier = NSUserInterfaceItemIdentifier(
            "Cadence.TrackTable.Row"
        )
        static let cellIdentifier = NSUserInterfaceItemIdentifier(
            "Cadence.TrackTable.HostingCell"
        )

        var parent: TrackTableCore
        var didReachEnd = false
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        var pendingPages: [Int: Task<Void, Never>] = [:]
        var previousVisibleRow: Int?
        var rangeAnchorRow: Int?
        var boundsObserver: NSObjectProtocol?
        var isRestoringSelection = false

        init(parent: TrackTableCore) {
            self.parent = parent
        }

        func attach(
            tableView: NSTableView,
            scrollView: NSScrollView
        ) {
            self.tableView = tableView
            self.scrollView = scrollView
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.visibleBoundsChanged()
                }
            }
            updateColumnWidth()
        }

        func detach() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
                self.boundsObserver = nil
            }
            pendingPages.values.forEach { $0.cancel() }
            pendingPages.removeAll()
        }

        func numberOfRows(in _: NSTableView) -> Int {
            parent.totalCount
        }

        func tableView(
            _: NSTableView,
            shouldSelectRow row: Int
        ) -> Bool {
            track(at: row) != nil
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor _: NSTableColumn?,
            row: Int
        ) -> NSView? {
            let cell = hostingCell(in: tableView)
            guard let track = track(at: row) else {
                cell.setRootView(AnyView(TrackTablePlaceholderRow()))
                request(pageContaining: row, direction: .none)
                return cell
            }

            let isSelected = parent.selection.contains(track.id)
            cell.setRootView(
                AnyView(
                    ProductionTrackTableRow(
                        model: parent.model,
                        track: track,
                        queue: parent.virtualWindow == nil
                            ? parent.tracks
                            : [track],
                        columns: parent.columns,
                        widths: parent.widths,
                        playlistID: parent.playlistID,
                        queueSource: parent.queueSource,
                        reorderAction: parent.reorderAction,
                        actionTrackIDs: actionTrackIDs(for: track.id),
                        isSelected: isSelected,
                        isFocused: isSelected
                            && tableView.window?.firstResponder === tableView,
                        select: { [weak self] in
                            self?.select(row: row)
                        }
                    )
                )
            )
            requestNextPageIfNeeded(row: row)
            return cell
        }

        func tableViewSelectionDidChange(_: Notification) {
            guard !isRestoringSelection, let tableView else {
                return
            }
            parent.selection = Set(
                tableView.selectedRowIndexes.compactMap {
                    track(at: $0)?.id
                }
            )
            reloadVisibleRows()
        }

        func visibleBoundsChanged() {
            updateColumnWidth()
            requestVisibleRows()
        }

        func requestVisibleRows() {
            guard
                let tableView,
                parent.virtualWindow != nil,
                parent.totalCount > 0
            else {
                return
            }
            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.length > 0 else {
                return
            }
            let firstRow = max(visible.location, 0)
            let lastRow = min(
                visible.location + visible.length - 1,
                parent.totalCount - 1
            )
            guard firstRow <= lastRow else {
                return
            }

            let direction: TrackViewportPrefetchDirection = if let previousVisibleRow {
                if firstRow < previousVisibleRow {
                    .before
                } else if firstRow > previousVisibleRow {
                    .after
                } else {
                    .none
                }
            } else {
                .after
            }
            previousVisibleRow = firstRow
            request(pageContaining: firstRow, direction: direction)
            request(pageContaining: lastRow, direction: direction)
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
                forRowIndexes: IndexSet(
                    integersIn: visible.location ..< (
                        visible.location + visible.length
                    )
                ),
                columnIndexes: IndexSet(integer: 0)
            )
        }

        func restoreSelection() {
            guard let tableView else {
                return
            }
            let indexes = IndexSet(
                parent.selection.compactMap(index(of:))
            )
            guard indexes != tableView.selectedRowIndexes else {
                return
            }
            isRestoringSelection = true
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            isRestoringSelection = false
        }

        func updateColumnWidth() {
            guard
                let tableView,
                let scrollView,
                let column = tableView.tableColumns.first
            else {
                return
            }
            let width = max(scrollView.contentSize.width, 1)
            if abs(column.width - width) > 0.5 {
                column.minWidth = 1
                column.maxWidth = .greatestFiniteMagnitude
                column.width = width
            }
        }
    }
}
