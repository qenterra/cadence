import AppKit
import SwiftUI

enum TrackTablePullRefreshPolicy {
    static let threshold: CGFloat = 72

    static func progress(for pullDistance: CGFloat) -> Double {
        Double(min(max(pullDistance, 0) / threshold, 1))
    }

    static func shouldRefresh(maximumPull: CGFloat) -> Bool {
        maximumPull >= threshold
    }
}

extension TrackTableCore {
    @MainActor
    // The coordinator deliberately owns the complete reusable NSTableView lifecycle.
    // swiftlint:disable:next type_body_length
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let columnIdentifier = NSUserInterfaceItemIdentifier(
            "Cadence.TrackTable.Row"
        )
        static let cellIdentifier = NSUserInterfaceItemIdentifier(
            "Cadence.TrackTable.NativeCell"
        )
        static let hostingCellIdentifier = NSUserInterfaceItemIdentifier(
            "Cadence.TrackTable.HostingCell"
        )

        var parent: TrackTableCore
        let queueIDProvider: TrackTableQueueIDProvider
        var renderedState: TrackTableRenderedState?
        var didReachEnd = false
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        var pendingPages: [Int: Task<Void, Never>] = [:]
        var pendingPageGenerations: [Int: UInt64] = [:]
        var pendingPageTokens: [Int: UInt64] = [:]
        var requestGeneration: UInt64 = 0
        var nextPageToken: UInt64 = 0
        var previousVisibleRow: Int?
        var lastPrefetchDirection: TrackViewportPrefetchDirection?
        var lastProcessedVisibleRows: IndexSet?
        var rangeAnchorRow: Int?
        var actionSelectionCache: TrackTableActionSelectionCache?
        var configuredVirtualRowStamps: [Int: TrackTableRowStamp] = [:]
        var boundsObserver: NSObjectProtocol?
        var liveScrollObservers: [NSObjectProtocol] = []
        var isRestoringSelection = false
        var refreshTask: Task<Void, Never>?
        weak var refreshIndicator: NSProgressIndicator?
        var maximumRefreshPull: CGFloat = 0
        let interactionState = TrackTableInteractionState()
        let displayProjectionCache: TrackRowDisplayProjectionCache
        var menuActionTargets: [TrackTableMenuActionTarget] = []
        var reduceMotion = NSWorkspace.shared
            .accessibilityDisplayShouldReduceMotion

        init(parent: TrackTableCore) {
            self.parent = parent
            queueIDProvider = TrackTableQueueIDProvider(
                snapshot: parent.snapshot
            )
            displayProjectionCache = TrackRowDisplayProjectionCache(
                probe: parent.workProbe
            )
        }

        isolated deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            for observer in liveScrollObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(
            tableView: NSTableView,
            scrollView: NSScrollView
        ) {
            removeScrollObservers()
            interactionState.endLiveScroll()
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
            let center = NotificationCenter.default
            liveScrollObservers = [
                center.addObserver(
                    forName: NSScrollView.willStartLiveScrollNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.liveScrollDidBegin()
                    }
                },
                center.addObserver(
                    forName: NSScrollView.didEndLiveScrollNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.liveScrollDidEnd()
                    }
                },
            ]
            updateColumnWidth()
        }

        func detach() {
            removeScrollObservers()
            interactionState.endLiveScroll()
            resetPagingRequests()
            refreshTask?.cancel()
            refreshTask = nil
            refreshIndicator?.removeFromSuperview()
            refreshIndicator = nil
            maximumRefreshPull = 0
        }

        func updateRefreshAffordance() {
            guard let scrollView else {
                return
            }
            guard parent.refreshAction != nil else {
                refreshIndicator?.removeFromSuperview()
                refreshIndicator = nil
                maximumRefreshPull = 0
                return
            }
            guard refreshIndicator == nil else {
                return
            }
            scrollView.verticalScrollElasticity = .allowed
            let indicator = NSProgressIndicator()
            indicator.controlSize = .small
            indicator.style = .spinning
            indicator.isIndeterminate = false
            indicator.minValue = 0
            indicator.maxValue = 1
            indicator.doubleValue = 0
            indicator.alphaValue = 0
            indicator.isDisplayedWhenStopped = true
            indicator.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(
                indicator,
                positioned: .above,
                relativeTo: scrollView.contentView
            )
            NSLayoutConstraint.activate([
                indicator.centerXAnchor.constraint(
                    equalTo: scrollView.centerXAnchor
                ),
                indicator.topAnchor.constraint(
                    equalTo: scrollView.topAnchor,
                    constant: 10
                ),
                indicator.widthAnchor.constraint(equalToConstant: 16),
                indicator.heightAnchor.constraint(equalToConstant: 16),
            ])
            refreshIndicator = indicator
        }

        private func liveScrollDidBegin() {
            interactionState.beginLiveScroll()
            resetVisiblePointerHover()
            guard refreshTask == nil else {
                return
            }
            maximumRefreshPull = 0
            prepareRefreshIndicatorForPull()
        }

        private func liveScrollDidEnd() {
            interactionState.endLiveScroll()
            reconcileVisiblePointerHover()
            let shouldRefresh = TrackTablePullRefreshPolicy.shouldRefresh(
                maximumPull: maximumRefreshPull
            )
            maximumRefreshPull = 0
            if shouldRefresh {
                beginRefresh()
            } else {
                hideRefreshIndicator()
            }
        }

        private func updateRefreshPullProgress() {
            guard refreshTask == nil, let scrollView, let refreshIndicator else {
                return
            }
            let pullDistance = max(0, -scrollView.contentView.bounds.minY)
            maximumRefreshPull = max(maximumRefreshPull, pullDistance)
            let progress = TrackTablePullRefreshPolicy.progress(
                for: pullDistance
            )
            refreshIndicator.doubleValue = progress
            refreshIndicator.alphaValue = progress > 0 ? 1 : 0
        }

        private func beginRefresh() {
            guard refreshTask == nil, let action = parent.refreshAction else {
                hideRefreshIndicator()
                return
            }
            refreshIndicator?.isIndeterminate = true
            refreshIndicator?.alphaValue = 1
            refreshIndicator?.startAnimation(nil)
            refreshTask = Task { @MainActor [weak self] in
                await action()
                guard !Task.isCancelled else {
                    return
                }
                self?.refreshIndicator?.stopAnimation(nil)
                self?.refreshIndicator?.isIndeterminate = false
                self?.refreshIndicator?.doubleValue = 0
                self?.hideRefreshIndicator()
                self?.refreshTask = nil
            }
        }

        private func prepareRefreshIndicatorForPull() {
            refreshIndicator?.stopAnimation(nil)
            refreshIndicator?.isIndeterminate = false
            refreshIndicator?.doubleValue = 0
            refreshIndicator?.alphaValue = 0
        }

        private func hideRefreshIndicator() {
            guard let refreshIndicator else {
                return
            }
            if reduceMotion {
                refreshIndicator.alphaValue = 0
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                refreshIndicator.animator().alphaValue = 0
            }
        }

        private func removeScrollObservers() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
                self.boundsObserver = nil
            }
            for observer in liveScrollObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            liveScrollObservers.removeAll(keepingCapacity: true)
        }

        func numberOfRows(in _: NSTableView) -> Int {
            parent.totalCount
        }

        func refreshAccessibilityPreferences() {
            reduceMotion = NSWorkspace.shared
                .accessibilityDisplayShouldReduceMotion
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
            if parent.renderer == .native {
                return nativeView(
                    in: tableView,
                    row: row
                )
            }
            let cell = hostingCell(in: tableView)
            guard let track = track(at: row) else {
                cell.configure(.placeholder(row: row))
                commitConfiguredVirtualStamp(.placeholder, at: row)
                request(pageContaining: row)
                return cell
            }

            let isSelected = parent.selection.contains(track.id)
            let actionTrackIDs = actionTrackIDs(for: track.id)
            let reorderAction: (([UUID]) -> Void)? = if parent.reorderAction
                != nil {
                { [weak self] trackIDs in
                    self?.parent.reorderAction?(trackIDs)
                }
            } else {
                nil
            }
            cell.configure(
                .track(
                    TrackTableRowConfiguration(
                        model: parent.model,
                        track: track,
                        queueIDProvider: queueIDProvider,
                        columns: parent.columns,
                        widths: parent.widths,
                        playlistID: parent.playlistID,
                        queueSource: parent.queueSource,
                        reorderAction: reorderAction,
                        resolveDraggedTrackIDs: { [weak self] sourceIDs in
                            self?.draggedTrackIDs(for: sourceIDs) ?? sourceIDs
                        },
                        actionTrackIDs: actionTrackIDs,
                        isSelected: isSelected,
                        isFocused: isSelected
                            && actionTrackIDs.first == track.id
                            && tableHasFocus(tableView),
                        artworkLoader: nil,
                        artworkWorkProbe: nil,
                        interactionState: interactionState,
                        workProbe: parent.workProbe,
                        select: { [weak self] in
                            self?.select(row: row)
                        }
                    )
                )
            )
            commitConfiguredVirtualStamp(.track(track), at: row)
            requestNextPageIfNeeded(row: row)
            return cell
        }

        private func nativeView(
            in tableView: NSTableView,
            row: Int
        ) -> NativeTrackTableCell {
            let cell = nativeCell(in: tableView)
            guard let track = track(at: row) else {
                cell.configure(
                    .placeholder,
                    columns: parent.columns,
                    widths: parent.widths,
                    isSelected: false,
                    isFocused: false,
                    isLiveScrolling: interactionState.isLiveScrolling,
                    reduceMotion: reduceMotion
                )
                commitConfiguredVirtualStamp(.placeholder, at: row)
                request(pageContaining: row)
                return cell
            }

            let trackID = track.id
            let projection = displayProjectionCache.resolve(
                track: track,
                currentTrackID: parent.currentTrackID,
                isCurrentTrackPlaying: parent.isCurrentTrackPlaying
            )
            let isSelected = parent.selection.contains(trackID)
            let isFocused = isSelected
                && orderedSelectedIDs().first == trackID
                && tableHasFocus(tableView)
            cell.configure(
                .track(projection),
                columns: parent.columns,
                widths: parent.widths,
                isSelected: isSelected,
                isFocused: isFocused,
                isLiveScrolling: interactionState.isLiveScrolling,
                reduceMotion: reduceMotion
            )
            commitConfiguredVirtualStamp(.track(track), at: row)
            requestNextPageIfNeeded(row: row)
            return cell
        }

        func tableViewSelectionDidChange(_: Notification) {
            guard !isRestoringSelection, let tableView else {
                return
            }
            let oldSelection = renderedState?.selection ?? parent.selection
            let newSelection = Set(
                tableView.selectedRowIndexes.compactMap {
                    track(at: $0)?.id
                }
            )
            if oldSelection != newSelection {
                invalidateActionSelectionCache()
            }
            parent.selection = newSelection
            renderedState?.selection = newSelection
            reloadRows(
                IndexSet(
                    oldSelection.union(newSelection).compactMap(index(of:))
                )
            )
        }

        func visibleBoundsChanged() {
            updateColumnWidth()
            updateRefreshPullProgress()
            if interactionState.isLiveScrolling {
                resetVisiblePointerHover()
            } else {
                reconcileVisiblePointerHover()
            }
            guard parent.virtualWindow != nil else {
                return
            }
            let visibleRows = visibleRowIndexes()
            guard
                visibleRows != lastProcessedVisibleRows
                || visibleRowsNeedLoad(visibleRows)
            else {
                return
            }
            lastProcessedVisibleRows = visibleRows
            refreshRenderedVirtualStamps(visibleRows: visibleRows)
            requestVisibleRows(visibleRows: visibleRows)
        }

        func reloadRows(_ rows: IndexSet) {
            guard let tableView else {
                return
            }
            let validRows = rows.intersection(
                IndexSet(integersIn: 0 ..< max(parent.totalCount, 0))
            )
            guard !validRows.isEmpty else {
                return
            }
            parent.workProbe?.recordReload(rows: validRows.count)
            tableView.reloadData(
                forRowIndexes: validRows,
                columnIndexes: IndexSet(integer: 0)
            )
        }

        func apply(_ reload: TrackTableReload) {
            queueIDProvider.update(from: parent.snapshot)
            switch reload {
            case .none:
                break
            case .all:
                rangeAnchorRow = nil
                if parent.virtualWindow != nil {
                    let representedSelection = representedSelectedIDs()
                    if representedSelection != parent.selection {
                        invalidateActionSelectionCache()
                        parent.selection = representedSelection
                    }
                }
                configuredVirtualRowStamps.removeAll(keepingCapacity: true)
                parent.workProbe?.recordFullReload()
                tableView?.reloadData()
                didReachEnd = false
            case let .rows(rows):
                reloadRows(rows)
            case let .changes(changes):
                apply(changes)
            }
        }

        private func apply(_ changes: TrackTableChanges) {
            guard let tableView else {
                return
            }
            parent.workProbe?.recordStructuralChanges(changes)
            if !changes.removedRows.isEmpty
                || !changes.insertedRows.isEmpty
                || !changes.movedRows.isEmpty {
                tableView.beginUpdates()
                if !changes.removedRows.isEmpty {
                    tableView.removeRows(
                        at: changes.removedRows,
                        withAnimation: []
                    )
                }
                if !changes.insertedRows.isEmpty {
                    tableView.insertRows(
                        at: changes.insertedRows,
                        withAnimation: []
                    )
                }
                for move in changes.movedRows {
                    tableView.moveRow(at: move.from, to: move.to)
                }
                tableView.endUpdates()
            }
            reloadRows(changes.reloadedRows)
        }

        func reconcileVirtualSelection() {
            rangeAnchorRow = nil
            let representedSelection = representedSelectedIDs()
            if representedSelection != parent.selection {
                invalidateActionSelectionCache()
                parent.selection = representedSelection
            }
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
            parent.workProbe?.recordSelectionRestore()
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
            if abs(tableView.frame.width - width) > 0.5 {
                var frame = tableView.frame
                frame.size.width = width
                parent.workProbe?.recordTableFrameWrite()
                tableView.frame = frame
            }
            if abs(column.width - width) > 0.5 {
                column.minWidth = 1
                column.maxWidth = .greatestFiniteMagnitude
                parent.workProbe?.recordColumnWidthWrite()
                column.width = width
            }
            let origin = scrollView.contentView.bounds.origin
            if abs(origin.x) > 0.5 {
                scrollView.contentView.scroll(
                    to: NSPoint(x: 0, y: origin.y)
                )
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        func visibleRowIndexes(totalCount: Int? = nil) -> IndexSet {
            let totalCount = totalCount ?? parent.totalCount
            guard let tableView, totalCount > 0 else {
                return []
            }
            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.length > 0 else {
                return []
            }
            let lowerBound = max(visible.location, 0)
            let upperBound = min(
                visible.location + visible.length,
                totalCount
            )
            guard lowerBound < upperBound else {
                return []
            }
            return IndexSet(integersIn: lowerBound ..< upperBound)
        }

        private func resetVisiblePointerHover() {
            forEachVisibleNativeCell { cell in
                cell.resetPointerHover()
            }
        }

        private func reconcileVisiblePointerHover() {
            guard let windowPoint = tableView?.window?
                .mouseLocationOutsideOfEventStream else {
                resetVisiblePointerHover()
                return
            }
            forEachVisibleNativeCell { cell in
                cell.reconcilePointerHover(at: windowPoint)
            }
        }

        private func forEachVisibleNativeCell(
            _ action: (NativeTrackTableCell) -> Void
        ) {
            guard let tableView else {
                return
            }
            for row in visibleRowIndexes() {
                guard let cell = tableView.view(
                    atColumn: 0,
                    row: row,
                    makeIfNecessary: false
                ) as? NativeTrackTableCell else {
                    continue
                }
                action(cell)
            }
        }

        func resetPagingRequests() {
            requestGeneration &+= 1
            cancelPendingPageRequests(except: [])
            previousVisibleRow = nil
            lastPrefetchDirection = nil
            lastProcessedVisibleRows = nil
            didReachEnd = false
        }

        private func visibleRowsNeedLoad(_ visibleRows: IndexSet) -> Bool {
            guard
                let window = parent.virtualWindow,
                let firstRow = visibleRows.first,
                let lastRow = visibleRows.last
            else {
                return false
            }
            let firstPage = firstRow / window.pageSize
            if window.needsLoad(page: firstPage),
               pendingPages[firstPage] == nil {
                return true
            }
            let lastPage = lastRow / window.pageSize
            return lastPage != firstPage
                && window.needsLoad(page: lastPage)
                && pendingPages[lastPage] == nil
        }
    }
}

extension TrackTableCore.Coordinator {
    func tableFocusDidChange() {
        guard
            let leadTrackID = orderedSelectedIDs().first,
            let leadRow = index(of: leadTrackID)
        else {
            return
        }
        reloadRows(IndexSet(integer: leadRow))
    }

    func requestVisibleRows() {
        requestVisibleRows(visibleRows: visibleRowIndexes())
    }

    func requestVisibleRows(visibleRows: IndexSet) {
        guard let window = parent.virtualWindow else {
            return
        }
        guard let firstRow = visibleRows.first else {
            cancelPendingPageRequests(except: [])
            previousVisibleRow = nil
            lastPrefetchDirection = nil
            return
        }
        parent.workProbe?.recordViewportRequest()

        let direction = retainedPrefetchDirection(observing: firstRow)
        let visiblePages = window.desiredPages(for: visibleRows)
        let prefetchPages = directionalPrefetchPages(
            in: window,
            visiblePages: visiblePages,
            direction: direction
        )
        let desiredPages = Set(visiblePages + prefetchPages)
        cancelPendingPageRequests(except: desiredPages)
        for page in visiblePages + prefetchPages {
            request(page: page)
        }
    }

    private func retainedPrefetchDirection(
        observing firstRow: Int
    ) -> TrackViewportPrefetchDirection {
        let observedDirection: TrackViewportPrefetchDirection = if let previousVisibleRow {
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
        switch observedDirection {
        case .before, .after:
            lastPrefetchDirection = observedDirection
        case .none:
            break
        }
        return lastPrefetchDirection ?? .after
    }

    private func directionalPrefetchPages(
        in window: LibraryTrackWindow,
        visiblePages: [Int],
        direction: TrackViewportPrefetchDirection
    ) -> [Int] {
        switch direction {
        case .before:
            visiblePages.first.map {
                window.prefetchCandidates(
                    around: $0,
                    direction: direction
                )
            } ?? []
        case .after:
            visiblePages.last.map {
                window.prefetchCandidates(
                    around: $0,
                    direction: direction
                )
            } ?? []
        case .none:
            []
        }
    }
}
