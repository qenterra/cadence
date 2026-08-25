// Native table actions stay together so cell callbacks and menu routing share one owner.
// swiftlint:disable file_length

import AppKit

@MainActor
final class TrackTableMenuActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invokeMenuAction() {
        action()
    }
}

enum TrackTableActionSelectionSource: Equatable {
    case materialized(TrackTableProjectionIdentity)
    case virtual(TrackTableVirtualIdentity, revision: Int)
    case unavailable
}

struct TrackTableActionSelectionCache {
    let source: TrackTableActionSelectionSource
    let orderedIDs: [UUID]
}

extension TrackTableCore.Coordinator {
    func tableView(
        _: NSTableView,
        pasteboardWriterForRow row: Int
    ) -> (any NSPasteboardWriting)? {
        guard
            parent.reorderAction != nil,
            ownsPlaylistContext,
            let track = track(at: row)
        else {
            return nil
        }
        let draggedIDs = draggedTrackIDs(for: [track.id])
        let orderedIDs = queueIDProvider.orderedIDs.filter(
            draggedIDs.contains
        )
        guard !orderedIDs.isEmpty else {
            return nil
        }
        let item = NSPasteboardItem()
        item.setString(
            orderedIDs.map(\.uuidString).joined(separator: ","),
            forType: .string
        )
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation operation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard
            parent.reorderAction != nil,
            ownsPlaylistContext,
            operation == .above,
            row >= 0,
            row <= parent.totalCount,
            !dragPayloads(from: info).isEmpty
        else {
            return []
        }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(
        _: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation operation: NSTableView.DropOperation
    ) -> Bool {
        guard operation == .above else {
            return false
        }
        return acceptNativeDrop(
            payloads: dragPayloads(from: info),
            beforeRow: row
        )
    }

    func acceptNativeDrop(
        payload: String,
        beforeRow row: Int
    ) -> Bool {
        acceptNativeDrop(payloads: [payload], beforeRow: row)
    }

    func acceptNativeDrop(
        payloads: [String],
        beforeRow row: Int
    ) -> Bool {
        guard
            ownsPlaylistContext,
            let reorderAction = parent.reorderAction,
            row >= 0,
            row <= parent.totalCount
        else {
            return false
        }
        let sourceIDs = Set(
            payloads
                .flatMap { $0.split(separator: ",") }
                .compactMap { UUID(uuidString: String($0)) }
        )
        let movingIDs = draggedTrackIDs(for: sourceIDs)
        guard !movingIDs.isEmpty else {
            return false
        }
        let reordered: [UUID]
        if let targetID = row < queueIDProvider.orderedIDs.count
            ? queueIDProvider.orderedIDs[row]
            : nil {
            reordered = queueIDProvider.reorderedIDs(
                moving: movingIDs,
                before: targetID
            )
        } else {
            let movingInOrder = queueIDProvider.orderedIDs.filter(
                movingIDs.contains
            )
            reordered = queueIDProvider.orderedIDs.filter {
                !movingIDs.contains($0)
            } + movingInOrder
        }
        guard reordered != queueIDProvider.orderedIDs else {
            return false
        }
        reorderAction(reordered)
        return true
    }

    private func dragPayloads(
        from info: any NSDraggingInfo
    ) -> [String] {
        info.draggingPasteboard.pasteboardItems?.compactMap {
            $0.string(forType: .string)
        } ?? []
    }

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
        case let .removeFromPlaylist(playlistID):
            guard ownsPlaylistContext else {
                return
            }
            Task {
                await parent.model.librarySession.store
                    .removeFromSelectedPlaylist(
                        playlistID: playlistID,
                        trackIDs: trackIDs
                    )
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
        return parent.snapshot?.indexByID[trackID]
    }

    func select(
        row: Int,
        modifiers: TrackTableSelectionModifiers? = nil
    ) {
        guard let tableView, track(at: row) != nil else {
            return
        }
        let modifiers = modifiers ?? TrackTableSelectionModifiers(
            NSApp.currentEvent?.modifierFlags ?? []
        )
        if modifiers.isRange, let rangeAnchorRow {
            let bounds = min(rangeAnchorRow, row) ... max(
                rangeAnchorRow,
                row
            )
            tableView.selectRowIndexes(
                IndexSet(integersIn: bounds),
                byExtendingSelection: false
            )
        } else if modifiers.isAdditive {
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

    func prepareSelectionForContextMenu(
        row: Int,
        modifiers: TrackTableSelectionModifiers
    ) {
        guard let tableView, track(at: row) != nil else {
            return
        }
        let selection = TrackTableContextSelection.resolve(
            clickedRow: row,
            selectedRows: tableView.selectedRowIndexes,
            modifiers: modifiers
        )
        if selection != tableView.selectedRowIndexes {
            tableView.selectRowIndexes(
                selection,
                byExtendingSelection: false
            )
        }
        if selection.contains(row) {
            rangeAnchorRow = row
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

    var ownsPlaylistContext: Bool {
        var playlistIDs: [UUID] = []
        if case let .playlist(playlistID) = parent.context {
            playlistIDs.append(playlistID)
        }
        if let playlistID = parent.playlistID {
            playlistIDs.append(playlistID)
        }
        if let queueSource = parent.queueSource,
           case let .playlist(playlistID) = queueSource {
            playlistIDs.append(playlistID)
        }
        guard let playlistID = playlistIDs.first else {
            return true
        }
        guard playlistIDs.allSatisfy({ $0 == playlistID }) else {
            return false
        }
        return parent.model.librarySession.store
            .ownsSelectedPlaylistTracks(for: playlistID)
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
        let source = actionSelectionSource
        if let actionSelectionCache,
           actionSelectionCache.source == source {
            return actionSelectionCache.orderedIDs
        }
        parent.workProbe?.recordActionSelectionResolution()
        let selectedIDs = representedSelectedIDs()
        let visibleOrder = if parent.virtualWindow == nil {
            parent.snapshot?.orderedIDs ?? []
        } else {
            selectedIDs.sorted {
                (index(of: $0) ?? .max) < (index(of: $1) ?? .max)
            }
        }
        let orderedIDs = TrackBulkActionResolver.orderedSelection(
            selectedIDs: selectedIDs,
            visibleOrder: visibleOrder
        )
        actionSelectionCache = TrackTableActionSelectionCache(
            source: source,
            orderedIDs: orderedIDs
        )
        return orderedIDs
    }

    var actionSelectionSource: TrackTableActionSelectionSource {
        if let snapshot = parent.snapshot {
            return .materialized(snapshot.identity)
        }
        guard let window = parent.virtualWindow else {
            return .unavailable
        }
        return .virtual(
            TrackTableVirtualIdentity(
                windowID: ObjectIdentifier(window),
                query: window.query,
                totalCount: window.totalCount,
                contentVersion: window.contentVersion
            ),
            revision: window.revision
        )
    }

    func invalidateActionSelectionCache() {
        actionSelectionCache = nil
    }

    func draggedTrackIDs(for sourceIDs: Set<UUID>) -> Set<UUID> {
        guard !parent.selection.isDisjoint(with: sourceIDs) else {
            return sourceIDs
        }
        return Set(orderedSelectedIDs())
    }

    func tableHasFocus(_ tableView: NSTableView) -> Bool {
        if let tableView = tableView as? TrackTableView {
            return tableView.hasTableFocus
        }
        return tableView.window?.firstResponder === tableView
    }

    func representedSelectedIDs() -> Set<UUID> {
        guard parent.virtualWindow != nil else {
            return parent.selection
        }
        return Set(parent.selection.filter { index(of: $0) != nil })
    }

    func title(for trackID: UUID) -> String {
        if let index = index(of: trackID),
           let track = track(at: index) {
            return track.title
        }
        return "Selected Track"
    }

    func request(pageContaining row: Int) {
        guard let window = parent.virtualWindow else {
            return
        }
        request(page: row / window.pageSize)
    }

    func request(page: Int) {
        guard let window = parent.virtualWindow else {
            return
        }
        guard
            window.needsLoad(page: page),
            pendingPages[page] == nil
        else {
            return
        }
        let generation = requestGeneration
        nextPageToken &+= 1
        let token = nextPageToken
        pendingPageGenerations[page] = generation
        pendingPageTokens[page] = token
        parent.workProbe?.recordPageTaskStart()
        pendingPages[page] = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await window.load(
                page: page,
                allowsPrefetch: false,
                prefetchDirection: .none,
                reportsFirstPageLoading: false
            )
            let wasCancelled = Task.isCancelled
            finishPageRequest(
                page: page,
                generation: generation,
                token: token
            )
            if wasCancelled {
                retryCancelledPageIfVisible(
                    page: page,
                    generation: generation,
                    window: window
                )
            }
        }
    }

    func retryCancelledPageIfVisible(
        page: Int,
        generation: UInt64,
        window: LibraryTrackWindow
    ) {
        guard
            requestGeneration == generation,
            boundsObserver != nil,
            let currentWindow = parent.virtualWindow,
            currentWindow === window,
            window.desiredPages(
                for: visibleRowIndexes()
            ).contains(page)
        else {
            return
        }
        request(page: page)
    }

    func cancelPendingPageRequests(except desiredPages: Set<Int>) {
        let obsoletePages = pendingPages.keys.filter {
            !desiredPages.contains($0)
        }
        for page in obsoletePages {
            let task = pendingPages.removeValue(forKey: page)
            pendingPageGenerations[page] = nil
            pendingPageTokens[page] = nil
            task?.cancel()
        }
    }

    @discardableResult
    func finishPageRequest(
        page: Int,
        generation: UInt64,
        token: UInt64? = nil
    ) -> Bool {
        guard
            requestGeneration == generation,
            pendingPageGenerations[page] == generation
        else {
            return false
        }
        if let token, pendingPageTokens[page] != token {
            return false
        }
        pendingPages[page] = nil
        pendingPageGenerations[page] = nil
        pendingPageTokens[page] = nil
        return true
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
            withIdentifier: Self.hostingCellIdentifier,
            owner: nil
        ) as? TrackTableHostingCell {
            return reused
        }
        let cell = TrackTableHostingCell(probe: parent.workProbe)
        cell.identifier = Self.hostingCellIdentifier
        return cell
    }

    func nativeCell(
        in tableView: NSTableView
    ) -> NativeTrackTableCell {
        if let reused = tableView.makeView(
            withIdentifier: Self.cellIdentifier,
            owner: nil
        ) as? NativeTrackTableCell {
            return reused
        }
        let cell = NativeTrackTableCell(probe: parent.workProbe)
        cell.artworkLoader = { [weak self] id, variant in
            guard let self else {
                return nil
            }
            return await parent.model.playbackArtworkAsset(
                id: id,
                variant: variant
            )
        }
        cell.onAction = { [weak self] trackID, action in
            self?.handleNativeAction(trackID: trackID, action: action)
        }
        cell.onActionsMenu = { [weak self] trackID, button in
            self?.showActionsMenu(for: trackID, from: button)
        }
        cell.onContextMenu = { [weak self] trackID, event in
            guard let self, let row = index(of: trackID) else {
                return nil
            }
            prepareSelectionForContextMenu(
                row: row,
                modifiers: TrackTableSelectionModifiers(
                    event.modifierFlags
                )
            )
            return actionsMenu(for: trackID)
        }
        return cell
    }

    func handleNativeAction(
        trackID: UUID,
        action: NativeTrackTableAction
    ) {
        switch action {
        case .select:
            guard let row = index(of: trackID) else {
                return
            }
            select(row: row)
        case .play:
            guard let row = index(of: trackID) else {
                return
            }
            play(row: row)
        case .favorite:
            toggleFavorite(trackID: trackID)
        case .artist:
            openArtist(for: trackID)
        case .album:
            openAlbum(for: trackID)
        }
    }

    func toggleFavorite(trackID: UUID) {
        guard
            let row = index(of: trackID),
            let track = track(at: row)
        else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            _ = await parent.model.setProductionTrackFavorite(
                track,
                isFavorite: !track.isFavorite
            )
        }
    }

    func openArtist(for trackID: UUID) {
        guard
            let row = index(of: trackID),
            let artistID = track(at: row)?.artistID
        else {
            return
        }
        parent.model.requestOpenProductionArtistContextually(id: artistID)
    }

    func openAlbum(for trackID: UUID) {
        guard
            let row = index(of: trackID),
            let albumID = track(at: row)?.albumID
        else {
            return
        }
        parent.model.requestOpenProductionAlbumContextually(id: albumID)
    }

    func showActionsMenu(
        for trackID: UUID,
        from button: NSButton
    ) {
        guard let menu = actionsMenu(for: trackID) else {
            return
        }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.maxY),
            in: button
        )
    }

    // Menu construction is intentionally linear so the enabled-state policy remains auditable.
    // swiftlint:disable:next function_body_length
    func actionsMenu(for trackID: UUID) -> NSMenu? {
        guard
            let row = index(of: trackID),
            let track = track(at: row)
        else {
            return nil
        }
        let actionTrackIDs = actionTrackIDs(for: trackID)
        let ownsContext = ownsPlaylistContext
        let menu = NSMenu()
        menu.autoenablesItems = false
        menuActionTargets.removeAll(keepingCapacity: true)

        appendMenuItem(
            to: menu,
            title: String(localized: "Play"),
            symbol: "play.fill",
            isEnabled: ownsContext
        ) { [weak self] in
            guard let row = self?.index(of: trackID) else {
                return
            }
            self?.play(row: row)
        }
        if let playlistID = parent.playlistID {
            appendMenuItem(
                to: menu,
                title: String(localized: "Remove from Playlist"),
                symbol: "minus.circle",
                isEnabled: ownsContext
            ) { [weak self] in
                guard let self else {
                    return
                }
                Task { @MainActor in
                    await parent.model.librarySession.store
                        .removeFromSelectedPlaylist(
                            playlistID: playlistID,
                            trackIDs: actionTrackIDs
                        )
                }
            }
        }
        appendMenuItem(
            to: menu,
            title: String(localized: "Play Next"),
            symbol: "text.line.first.and.arrowtriangle.forward",
            isEnabled: ownsContext
        ) { [weak self] in
            guard let self, ownsPlaylistContext else {
                return
            }
            parent.model.playProductionNext(actionTrackIDs)
        }
        appendMenuItem(
            to: menu,
            title: String(localized: "Add to Queue"),
            symbol: "text.badge.plus",
            isEnabled: ownsContext
        ) { [weak self] in
            guard let self, ownsPlaylistContext else {
                return
            }
            parent.model.addToProductionQueue(actionTrackIDs)
        }

        if actionTrackIDs.count == 1 {
            appendMenuItem(
                to: menu,
                title: track.isFavorite
                    ? String(localized: "Remove from Favorites")
                    : String(localized: "Add to Favorites"),
                symbol: track.isFavorite ? "heart.slash" : "heart"
            ) { [weak self] in
                self?.toggleFavorite(trackID: trackID)
            }
            appendMenuItem(
                to: menu,
                title: String(localized: "Edit Tags…"),
                symbol: "tag.badge.plus"
            ) { [weak self] in
                self?.parent.model.openProductionTagEditor(trackID: trackID)
            }
        }

        appendTagMenu(to: menu, trackIDs: actionTrackIDs)
        appendPlaylistMenu(to: menu, trackIDs: actionTrackIDs)
        if actionTrackIDs.count == 1 {
            appendArtworkItems(to: menu, trackID: trackID)
        }

        menu.addItem(.separator())
        appendMenuItem(
            to: menu,
            title: String(localized: "Move to Trash…"),
            symbol: "trash"
        ) { [weak self] in
            guard let self else {
                return
            }
            parent.model.requestLibraryDeletion(
                trackIDs: actionTrackIDs,
                title: actionTrackIDs.count == 1
                    ? track.title
                    : "\(actionTrackIDs.count) selected tracks"
            )
        }
        return menu
    }

    private func appendTagMenu(
        to menu: NSMenu,
        trackIDs: [UUID]
    ) {
        let submenu = NSMenu(title: String(localized: "Add Tag"))
        let tags = parent.model.librarySession.store.tags
        if tags.isEmpty {
            let empty = NSMenuItem(
                title: String(localized: "No Tags Yet"),
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for tag in tags {
                appendMenuItem(to: submenu, title: tag.displayPath) {
                    [weak self] in
                    guard let self else {
                        return
                    }
                    Task { @MainActor in
                        await parent.model.librarySession.store
                            .assignTagReportingFailure(
                                tag.id,
                                trackIDs: trackIDs
                            )
                    }
                }
            }
        }
        appendSubmenu(
            submenu,
            to: menu,
            title: String(localized: "Add Tag"),
            symbol: "tag.badge.plus"
        )
    }

    private func appendPlaylistMenu(
        to menu: NSMenu,
        trackIDs: [UUID]
    ) {
        let submenu = NSMenu(title: String(localized: "Add to Playlist"))
        let playlists = parent.model.librarySession.store.playlists
        for playlist in playlists {
            appendMenuItem(to: submenu, title: playlist.name) {
                [weak self] in
                guard let self else {
                    return
                }
                Task { @MainActor in
                    await parent.model.librarySession.store.addToPlaylist(
                        playlistID: playlist.id,
                        trackIDs: trackIDs
                    )
                }
            }
        }
        if !playlists.isEmpty {
            submenu.addItem(.separator())
        }
        appendMenuItem(
            to: submenu,
            title: String(localized: "New Playlist…"),
            symbol: "plus"
        ) { [weak self] in
            guard let self else {
                return
            }
            parent.model.requestPlaylistCreation(adding: trackIDs)
        }
        appendSubmenu(
            submenu,
            to: menu,
            title: String(localized: "Add to Playlist"),
            symbol: "text.badge.plus"
        )
    }

    private func appendArtworkItems(
        to menu: NSMenu,
        trackID: UUID
    ) {
        let target = ArtworkTarget.managedTrack(trackID)
        let hasArtwork = parent.model.hasCustomArtwork(for: target)
        appendMenuItem(
            to: menu,
            title: hasArtwork
                ? String(localized: "Replace Track Artwork")
                : String(localized: "Choose Track Artwork"),
            symbol: "photo"
        ) { [weak self] in
            self?.parent.model.requestArtworkImport(for: target)
        }
        if hasArtwork {
            appendMenuItem(
                to: menu,
                title: String(localized: "Remove Track Artwork"),
                symbol: "trash"
            ) { [weak self] in
                self?.parent.model.removeCustomArtwork(for: target)
            }
        }
    }

    private func appendSubmenu(
        _ submenu: NSMenu,
        to menu: NSMenu,
        title: String,
        symbol: String
    ) {
        let item = NSMenuItem(
            title: title,
            action: nil,
            keyEquivalent: ""
        )
        item.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        )
        item.submenu = submenu
        menu.addItem(item)
    }

    private func appendMenuItem(
        to menu: NSMenu,
        title: String,
        symbol: String? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        let target = TrackTableMenuActionTarget(action: action)
        menuActionTargets.append(target)
        let item = NSMenuItem(
            title: title,
            action: #selector(TrackTableMenuActionTarget.invokeMenuAction),
            keyEquivalent: ""
        )
        item.target = target
        item.isEnabled = isEnabled
        if let symbol {
            item.image = NSImage(
                systemSymbolName: symbol,
                accessibilityDescription: nil
            )
        }
        menu.addItem(item)
    }

    func renderedSource(
        for parent: TrackTableCore,
        visibleRows: IndexSet
    ) -> TrackTableRenderedSource {
        if let snapshot = parent.snapshot {
            return .materialized(snapshot)
        }
        guard let window = parent.virtualWindow else {
            preconditionFailure("A track table must have one row source")
        }
        let identity = TrackTableVirtualIdentity(
            windowID: ObjectIdentifier(window),
            query: window.query,
            totalCount: window.totalCount,
            contentVersion: window.contentVersion
        )
        if let renderedState,
           case let .virtual(
               renderedIdentity,
               renderedRevision,
               renderedStamps
           ) = renderedState.source,
           renderedIdentity == identity,
           renderedRevision == window.revision,
           stamps(renderedStamps, cover: visibleRows) {
            return renderedState.source
        }
        return .virtual(
            identity: identity,
            revision: window.revision,
            stamps: rowStamps(
                in: visibleRows,
                window: window
            )
        )
    }

    func committedSource(
        after source: TrackTableRenderedSource,
        visibleRows: IndexSet
    ) -> TrackTableRenderedSource {
        guard
            case let .virtual(identity, revision, liveStamps) = source
        else {
            return source
        }
        if stamps(configuredVirtualRowStamps, cover: visibleRows),
           visibleRows.allSatisfy({
               configuredVirtualRowStamps[$0] == liveStamps[$0]
           }) {
            return source
        }
        let stamps = configuredVirtualRowStamps.filter {
            visibleRows.contains($0.key)
        }
        let isFullyCommitted = visibleRows.allSatisfy {
            stamps[$0] == liveStamps[$0]
        }
        let committedRevision: Int = if isFullyCommitted {
            revision
        } else if
            let renderedState,
            case let .virtual(
                oldIdentity,
                oldRevision,
                _
            ) = renderedState.source,
            oldIdentity == identity {
            oldRevision
        } else {
            revision
        }
        return .virtual(
            identity: identity,
            revision: committedRevision,
            stamps: stamps
        )
    }

    func rowStamps(
        in rows: IndexSet,
        window: LibraryTrackWindow
    ) -> [Int: TrackTableRowStamp] {
        var stamps: [Int: TrackTableRowStamp] = [:]
        stamps.reserveCapacity(rows.count)
        for index in rows {
            parent.workProbe?.recordVirtualStampRead()
            stamps[index] = window.track(at: index).map(
                TrackTableRowStamp.track
            ) ?? .placeholder
        }
        return stamps
    }

    func refreshRenderedVirtualStamps(visibleRows: IndexSet) {
        guard
            var renderedState,
            case let .virtual(identity, revision, _) = renderedState.source
        else {
            return
        }
        configuredVirtualRowStamps = configuredVirtualRowStamps.filter {
            visibleRows.contains($0.key)
        }
        renderedState.source = .virtual(
            identity: identity,
            revision: revision,
            stamps: configuredVirtualRowStamps
        )
        self.renderedState = renderedState
    }

    func commitConfiguredVirtualStamp(
        _ stamp: TrackTableRowStamp,
        at row: Int
    ) {
        guard let window = parent.virtualWindow else {
            return
        }
        let configuredStampChanged = configuredVirtualRowStamps[row]
            != stamp
        if configuredStampChanged {
            configuredVirtualRowStamps[row] = stamp
        }
        guard
            var renderedState,
            case let .virtual(
                identity,
                revision,
                stamps
            ) = renderedState.source,
            identity == TrackTableVirtualIdentity(
                windowID: ObjectIdentifier(window),
                query: window.query,
                totalCount: window.totalCount,
                contentVersion: window.contentVersion
            ),
            stamps[row] != stamp
        else {
            return
        }
        var committedStamps = stamps
        committedStamps[row] = stamp
        renderedState.source = .virtual(
            identity: identity,
            revision: revision,
            stamps: committedStamps
        )
        self.renderedState = renderedState
    }

    func stamps(
        _ stamps: [Int: TrackTableRowStamp],
        cover rows: IndexSet
    ) -> Bool {
        stamps.count == rows.count
            && rows.allSatisfy { stamps[$0] != nil }
    }
}
