import AppKit

extension TrackTableCore.Coordinator {
    @objc func playClickedRow() {
        guard let tableView else {
            return
        }
        let row = tableView.clickedRow >= 0
            ? tableView.clickedRow
            : tableView.selectedRow
        play(row: row)
    }

    func playSelectedRow() {
        play(row: tableView?.selectedRow ?? -1)
    }

    func togglePlayback() {
        _ = AppCommandRouter(model: parent.model).handle(
            .togglePlayback,
            focus: .trackTable
        )
    }

    func deleteSelection() {
        let trackIDs = orderedSelectedIDs()
        guard !trackIDs.isEmpty else {
            return
        }
        switch TrackBulkActionResolver.defaultDelete(
            for: parent.context
        ) {
        case .removeFromPlaylist:
            Task {
                await parent.model.librarySession.store
                    .removeFromSelectedPlaylist(trackIDs: trackIDs)
            }
        case .moveToTrash:
            parent.model.requestLibraryDeletion(
                trackIDs: trackIDs,
                title: trackIDs.count == 1
                    ? title(for: trackIDs[0])
                    : "\(trackIDs.count) selected tracks"
            )
        default:
            break
        }
    }

    func track(
        at row: Int
    ) -> LibraryTrackProjection? {
        guard row >= 0 else {
            return nil
        }
        if let virtualWindow = parent.virtualWindow {
            return virtualWindow.track(at: row)
        }
        return parent.tracks.indices.contains(row)
            ? parent.tracks[row]
            : nil
    }

    func index(
        of trackID: UUID
    ) -> Int? {
        if let virtualWindow = parent.virtualWindow {
            return virtualWindow.index(ofTrackID: trackID)
        }
        return parent.tracks.firstIndex { $0.id == trackID }
    }

    func select(row: Int) {
        guard let tableView, track(at: row) != nil else {
            return
        }
        let modifiers = NSApp.currentEvent?.modifierFlags
            .intersection(.deviceIndependentFlagsMask) ?? []
        if modifiers.contains(.shift), let rangeAnchorRow {
            let bounds = min(rangeAnchorRow, row) ... max(
                rangeAnchorRow,
                row
            )
            tableView.selectRowIndexes(
                IndexSet(integersIn: bounds),
                byExtendingSelection: false
            )
        } else if modifiers.contains(.command) {
            if tableView.selectedRowIndexes.contains(row) {
                tableView.deselectRow(row)
            } else {
                tableView.selectRowIndexes(
                    IndexSet(integer: row),
                    byExtendingSelection: true
                )
            }
            if rangeAnchorRow == nil {
                rangeAnchorRow = row
            }
        } else {
            rangeAnchorRow = row
            tableView.selectRowIndexes(
                IndexSet(integer: row),
                byExtendingSelection: false
            )
        }
        tableView.window?.makeFirstResponder(tableView)
    }

    func play(row: Int) {
        guard let track = track(at: row) else {
            return
        }
        parent.model.playProductionTrack(
            track,
            within: parent.virtualWindow == nil ? parent.tracks : [track],
            source: parent.queueSource ?? .adHoc
        )
    }

    func actionTrackIDs(
        for trackID: UUID
    ) -> [UUID] {
        guard parent.selection.contains(trackID) else {
            return [trackID]
        }
        return orderedSelectedIDs()
    }

    func orderedSelectedIDs() -> [UUID] {
        let visibleOrder = if parent.virtualWindow == nil {
            parent.tracks.map(\.id)
        } else {
            parent.selection.sorted {
                (index(of: $0) ?? .max) < (index(of: $1) ?? .max)
            }
        }
        return TrackBulkActionResolver.orderedSelection(
            selectedIDs: parent.selection,
            visibleOrder: visibleOrder
        )
    }

    func title(for trackID: UUID) -> String {
        if let index = index(of: trackID),
           let track = track(at: index) {
            return track.title
        }
        return "Selected Track"
    }

    func request(
        pageContaining row: Int,
        direction: TrackViewportPrefetchDirection
    ) {
        guard let window = parent.virtualWindow else {
            return
        }
        let page = row / window.pageSize
        guard pendingPages[page] == nil else {
            return
        }
        pendingPages[page] = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await window.load(
                page: page,
                prefetchDirection: direction
            )
            pendingPages[page] = nil
        }
    }

    func requestNextPageIfNeeded(row: Int) {
        guard
            parent.virtualWindow == nil,
            let onReachEnd = parent.onReachEnd,
            !didReachEnd,
            row >= max(parent.tracks.count - 8, 0)
        else {
            return
        }
        didReachEnd = true
        Task { @MainActor [weak self] in
            await onReachEnd()
            self?.didReachEnd = false
        }
    }

    func hostingCell(
        in tableView: NSTableView
    ) -> TrackTableHostingCell {
        if let reused = tableView.makeView(
            withIdentifier: Self.cellIdentifier,
            owner: nil
        ) as? TrackTableHostingCell {
            return reused
        }
        let cell = TrackTableHostingCell()
        cell.identifier = Self.cellIdentifier
        return cell
    }
}
