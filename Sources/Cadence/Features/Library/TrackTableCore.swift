import AppKit
import SwiftUI

struct TrackTableCore: NSViewRepresentable {
    let model: CadenceAppModel
    let context: TrackTableContext
    let tracks: [LibraryTrackProjection]
    let virtualWindow: LibraryTrackWindow?
    let columns: [TrackTableColumn]
    let widths: TrackTableResolvedWidths
    let playlistID: UUID?
    let queueSource: PlaybackQueueSource?
    let reorderAction: (([UUID]) -> Void)?
    let onReachEnd: (() async -> Void)?
    @Binding var selection: Set<UUID>

    var totalCount: Int {
        virtualWindow?.totalCount ?? tracks.count
    }

    var revision: Int {
        virtualWindow?.revision ?? tracks.count
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = TrackTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 58
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.playClickedRow)
        tableView.onReturn = { [weak coordinator = context.coordinator] in
            coordinator?.playSelectedRow()
        }
        tableView.onSpace = { [weak coordinator = context.coordinator] in
            coordinator?.togglePlayback()
        }
        tableView.onDelete = { [weak coordinator = context.coordinator] in
            coordinator?.deleteSelection()
        }

        let column = NSTableColumn(identifier: Coordinator.columnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
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
        coordinator.parent = self

        guard let tableView = scrollView.documentView as? NSTableView else {
            return
        }
        coordinator.updateColumnWidth()
        if previousCount != totalCount {
            tableView.noteNumberOfRowsChanged()
            coordinator.didReachEnd = false
        }
        if previousRevision != revision || previousCount == totalCount {
            coordinator.reloadVisibleRows()
        }
        coordinator.restoreSelection()
        coordinator.requestVisibleRows()
    }

    static func dismantleNSView(
        _: NSScrollView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }
}
