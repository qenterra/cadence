import AppKit
@testable import Cadence
import Foundation
import SwiftData
import SwiftUI
import Testing

extension AllTracksPerformanceTests {
    @Test(
        "Track-table focus notifications observe the completed responder transition",
        .appKitExclusive
    )
    func focusNotificationsObserveCompletedResponderTransition() async {
        let window = TrackTableFocusWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentLayoutRect)
        let focusProbe = TrackTableFocusProbeView(
            frame: NSRect(x: 20, y: 20, width: 180, height: 24)
        )
        let tableView = TrackTableView(
            frame: NSRect(x: 20, y: 60, width: 600, height: 380)
        )
        contentView.addSubview(focusProbe)
        contentView.addSubview(tableView)
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        await drainMainQueue()
        #expect(window.makeFirstResponder(focusProbe))

        var observedGain: Bool?
        tableView.onFocusChange = {
            observedGain = window.firstResponder === tableView
        }
        #expect(window.makeFirstResponder(tableView))
        await drainMainQueue()
        #expect(tableView.hasTableFocus)
        #expect(observedGain == true)

        var observedLoss: Bool?
        tableView.onFocusChange = {
            observedLoss = window.firstResponder === tableView
        }
        #expect(window.makeFirstResponder(focusProbe))
        await drainMainQueue()
        #expect(!tableView.hasTableFocus)
        #expect(observedLoss == false)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    @Test(
        "A 10k select-all viewport resolves one lead row and one shared action selection",
        .appKitExclusive
    )
    func selectAllViewportKeepsOneLeadAndOneActionSelection() async throws {
        let rows = makeTracks(count: 10000)
        let selection = Set(rows.map(\.id))
        let probe = TrackTableWorkProbe()
        let core = makeCore(
            rows: rows,
            selection: .constant(selection),
            probe: probe,
            sourceIndex: 50007
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = TrackTableView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 24 * 58)
        )
        let column = NSTableColumn(identifier: .init("row"))
        tableView.addTableColumn(column)
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        tableView.reloadData()

        let window = TrackTableFocusWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 24 * 58),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = tableView
        window.makeKeyAndOrderFront(nil)
        #expect(window.makeFirstResponder(tableView))

        var cells: [TrackTableHostingCell] = []
        let configurations = try (0 ..< 24).map { row in
            let cell = try #require(
                coordinator.tableView(
                    tableView,
                    viewFor: column,
                    row: row
                ) as? TrackTableHostingCell
            )
            guard case let .track(configuration) = cell.hostState.content else {
                Issue.record("Expected a configured track row")
                throw TrackTableSelectionTestError.missingTrackConfiguration
            }
            cells.append(cell)
            return configuration
        }
        #expect(configurations.filter(\.isFocused).count == 1)

        let resolvedSelections = configurations.map {
            coordinator.actionTrackIDs(for: $0.track.id)
        }
        let storageIDs = resolvedSelections.map { ids in
            ids.withUnsafeBufferPointer { buffer in
                UInt(bitPattern: buffer.baseAddress)
            }
        }
        #expect(Set(storageIDs).count == 1)
        #expect(probe.actionSelectionResolutions == 1)

        await drainMainQueue()
        tableView.delegate = nil
        tableView.dataSource = nil
        window.orderOut(nil)
        window.contentView = nil
        await drainMainQueue()
        cells.removeAll()
        await drainMainQueue()
        window.close()
        await drainMainQueue()
    }

    @Test("A one-UUID drag resolves the selected group only when dropped")
    func selectedDragResolvesGroupAtDropTime() {
        let rows = makeTracks(count: 10000)
        let orderedIDs = rows.map(\.id)
        let provider = TrackTableQueueIDProvider(
            snapshot: makeSnapshot(
                rows: rows,
                version: TrackTableContentVersion(
                    sourceID: deterministicUUID(50008),
                    generation: 0
                )
            )
        )
        var reorderedIDs: [UUID]?
        let row = ProductionTrackTableRow(
            model: presentationModel,
            track: rows[5000],
            queueIDProvider: provider,
            columns: [],
            widths: presentation.widths,
            playlistID: nil,
            queueSource: nil,
            reorderAction: { reorderedIDs = $0 },
            resolveDraggedTrackIDs: { _ in Set(orderedIDs) },
            actionTrackIDs: orderedIDs,
            isSelected: true,
            isFocused: true,
            artworkLoader: nil,
            artworkWorkProbe: nil,
            select: {}
        )

        #expect(row.dragPayload == rows[5000].id.uuidString)
        #expect(row.dragPayload.split(separator: ",").count == 1)
        #expect(row.reorder([rows[0].id.uuidString]))
        #expect(reorderedIDs == orderedIDs)
    }

    @Test("Fixed-height track hosts disable SwiftUI content sizing")
    func fixedHeightTrackHostsDisableContentSizing() {
        let cell = TrackTableHostingCell()

        #expect(cell.hostingSizingOptions.isEmpty)
    }

    @Test("A selection move reloads only the old and new rows")
    func selectionReloadsOnlyOldAndNewRows() {
        let tracks = makeTracks(count: 10000)
        var selection: Set<UUID> = [tracks[100].id]
        let probe = TrackTableWorkProbe()
        let core = TrackTableCore(
            model: CadenceAppModel.testFixture(),
            context: .library,
            snapshot: makeSnapshot(
                rows: tracks,
                version: TrackTableContentVersion(
                    sourceID: deterministicUUID(30000),
                    generation: 0
                )
            ),
            virtualWindow: nil,
            columns: [],
            widths: TrackTableResolvedWidths(
                song: 360,
                album: 220,
                year: 72,
                time: 72
            ),
            playlistID: nil,
            queueSource: .allTracks,
            reorderAction: nil,
            onReachEnd: nil,
            workProbe: probe,
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = RecordingTrackTableView(
            visibleRows: NSRange(location: 0, length: tracks.count)
        )
        tableView.addTableColumn(NSTableColumn(identifier: .init("row")))
        tableView.dataSource = coordinator
        coordinator.tableView = tableView
        tableView.reloadData()
        tableView.selectRowIndexes(
            IndexSet(integer: 9000),
            byExtendingSelection: false
        )

        coordinator.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification)
        )

        #expect(selection == [tracks[9000].id])
        #expect(
            tableView.reloadedRowSets
                == [IndexSet([100, 9000])]
        )
        #expect(probe.reloadedRows == 2)
    }

    @Test(
        "A virtual replacement cannot retain an unrepresented selection",
        arguments: VirtualSelectionReplacementScenario.allCases
    )
    func virtualReplacementClearsUnrepresentedSelection(
        _ scenario: VirtualSelectionReplacementScenario
    ) async throws {
        let initialRows = makeTracks(count: 48)
        let selectedRow = 5
        let selectedTrack = initialRows[selectedRow]
        let source = MutableTrackWindowSource()
        await source.replace(with: initialRows)
        let window = LibraryTrackWindow(
            pageSize: 24,
            pageCapacity: 1,
            prefetchPages: 0
        ) { _, offset, limit in
            await source.rows(offset: offset, limit: limit)
        }
        let contentVersion = TrackTableContentVersion(
            sourceID: deterministicUUID(21000),
            generation: 0
        )
        await window.configure(
            totalCount: initialRows.count,
            query: .allTracks,
            contentVersion: contentVersion
        )

        var selection: Set<UUID> = [selectedTrack.id]
        let core = makeVirtualCore(
            window: window,
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            ),
            probe: nil
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = RecordingTrackTableView(
            visibleRows: NSRange(location: 0, length: 24)
        )
        let column = NSTableColumn(identifier: .init("row"))
        tableView.addTableColumn(column)
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        coordinator.tableView = tableView
        for row in 0 ..< 24 {
            _ = coordinator.tableView(
                tableView,
                viewFor: column,
                row: row
            )
        }
        tableView.selectRowIndexes(
            IndexSet(integer: selectedRow),
            byExtendingSelection: false
        )
        coordinator.rangeAnchorRow = selectedRow
        let visibleRows = IndexSet(integersIn: 0 ..< 24)
        let initialSource = coordinator.renderedSource(
            for: core,
            visibleRows: visibleRows
        )
        coordinator.renderedState = TrackTableRenderedState(
            source: coordinator.committedSource(
                after: initialSource,
                visibleRows: visibleRows
            ),
            selection: selection,
            presentation: core.presentation
        )

        try await verifyVirtualReplacement(
            scenario,
            context: VirtualReplacementVerificationContext(
                initialRows: initialRows,
                selectedTrack: selectedTrack,
                source: source,
                window: window,
                contentVersion: contentVersion,
                selection: Binding(
                    get: { selection },
                    set: { selection = $0 }
                ),
                core: core,
                coordinator: coordinator,
                tableView: tableView,
                visibleRows: visibleRows
            )
        )
    }

    private func verifyVirtualReplacement(
        _ scenario: VirtualSelectionReplacementScenario,
        context: VirtualReplacementVerificationContext
    ) async throws {
        let replacement = scenario.replacement(
            initialRows: context.initialRows,
            selectedTrack: context.selectedTrack
        )
        await context.source.replace(with: replacement.rows)
        await context.window.configure(
            totalCount: replacement.rows.count,
            query: replacement.query,
            contentVersion: scenario.advancesContentVersion
                ? context.contentVersion.advanced()
                : context.contentVersion
        )
        let updatedCore = makeVirtualCore(
            window: context.window,
            selection: context.selection,
            probe: nil
        )
        let incomingSource = context.coordinator.renderedSource(
            for: updatedCore,
            visibleRows: context.visibleRows
        )
        let plan = TrackTableUpdatePlanner.plan(
            previous: context.coordinator.renderedState,
            source: incomingSource,
            selection: context.selection.wrappedValue,
            presentation: updatedCore.presentation,
            visibleRows: context.visibleRows
        )
        context.coordinator.parent = updatedCore
        if plan.resetsEndPaging {
            context.coordinator.resetPagingRequests()
        }
        context.coordinator.apply(plan.reload)
        if plan.restoresSelection {
            context.coordinator.restoreSelection()
        }
        context.coordinator.renderedState = TrackTableRenderedState(
            source: context.coordinator.committedSource(
                after: incomingSource,
                visibleRows: context.visibleRows
            ),
            selection: context.selection.wrappedValue,
            presentation: updatedCore.presentation
        )

        #expect(plan.reload == .all)
        #expect(context.tableView.selectedRowIndexes.isEmpty)
        #expect(context.selection.wrappedValue.isEmpty)
        #expect(context.coordinator.rangeAnchorRow == nil)
        #expect(context.coordinator.orderedSelectedIDs().isEmpty)
        let currentTrack = try #require(context.window.track(at: 0))
        #expect(
            context.coordinator.actionTrackIDs(for: currentTrack.id)
                == [currentTrack.id]
        )
        context.coordinator.deleteSelection()
        #expect(context.core.model.pendingLibraryDeletion == nil)
        context.core.model.cancelLibraryDeletion()
    }

    @Test("A semantic reorder remaps a cached offscreen selection")
    func semanticReorderRemapsCachedOffscreenSelection() async {
        let initialRows = makeTracks(count: 48)
        let selectedTrack = initialRows[30]
        let source = MutableTrackWindowSource()
        await source.replace(with: initialRows)
        let window = LibraryTrackWindow(
            pageSize: 24,
            pageCapacity: 2,
            prefetchPages: 0
        ) { _, offset, limit in
            await source.rows(offset: offset, limit: limit)
        }
        let initialVersion = TrackTableContentVersion(
            sourceID: deterministicUUID(21001),
            generation: 0
        )
        await window.configure(
            totalCount: initialRows.count,
            query: .allTracks,
            contentVersion: initialVersion
        )
        await window.load(
            page: 1,
            allowsPrefetch: false,
            prefetchDirection: .none
        )

        var selection: Set<UUID> = [selectedTrack.id]
        let probe = TrackTableWorkProbe()
        let selectionBinding = Binding(
            get: { selection },
            set: { selection = $0 }
        )
        let core = makeVirtualCore(
            window: window,
            selection: selectionBinding,
            probe: probe
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = RecordingTrackTableView(
            visibleRows: NSRange(location: 0, length: 24)
        )
        let column = NSTableColumn(identifier: .init("row"))
        tableView.addTableColumn(column)
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 24 * 58)
        )
        scrollView.documentView = tableView
        coordinator.attach(tableView: tableView, scrollView: scrollView)
        defer { coordinator.detach() }

        for row in 0 ..< 24 {
            _ = coordinator.tableView(
                tableView,
                viewFor: column,
                row: row
            )
        }
        tableView.selectRowIndexes(
            IndexSet(integer: 30),
            byExtendingSelection: false
        )
        coordinator.rangeAnchorRow = 30
        let visibleRows = IndexSet(integersIn: 0 ..< 24)
        let initialSource = coordinator.renderedSource(
            for: core,
            visibleRows: visibleRows
        )
        coordinator.renderedState = TrackTableRenderedState(
            source: coordinator.committedSource(
                after: initialSource,
                visibleRows: visibleRows
            ),
            selection: selection,
            presentation: core.presentation
        )

        var reorderedRows = initialRows
        reorderedRows.swapAt(30, 31)
        await source.replace(with: reorderedRows)
        await window.configure(
            totalCount: reorderedRows.count,
            query: .allTracks,
            contentVersion: initialVersion.advanced()
        )
        let updatedCore = makeVirtualCore(
            window: window,
            selection: selectionBinding,
            probe: probe
        )
        probe.reset()

        updatedCore.applyUpdate(
            to: scrollView,
            coordinator: coordinator
        )

        #expect(selection == [selectedTrack.id])
        #expect(tableView.selectedRowIndexes == IndexSet(integer: 31))
        #expect(coordinator.rangeAnchorRow == nil)
        #expect(probe.fullReloads == 0)
        #expect(probe.selectionRestores == 1)
    }

    @Test("A focus change reloads only the lead selected row")
    func focusChangeReconfiguresLeadSelectedRowOnly() {
        let rows = makeTracks(count: 1000)
        let selectedRows = IndexSet([100, 900])
        let selection = Set(selectedRows.map { rows[$0].id })
        let probe = TrackTableWorkProbe()
        let core = makeCore(
            rows: rows,
            selection: .constant(selection),
            probe: probe,
            sourceIndex: 50003
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = RecordingTrackTableView(
            visibleRows: NSRange(location: 0, length: rows.count)
        )
        tableView.addTableColumn(NSTableColumn(identifier: .init("row")))
        coordinator.tableView = tableView

        coordinator.tableFocusDidChange()

        #expect(tableView.reloadedRowSets == [IndexSet(integer: 100)])
        #expect(probe.reloadedRows == 1)
    }

    @Test("A stale page completion cannot clear a newer request")
    func stalePageCompletionCannotClearNewerRequest() {
        let core = makeCore(
            rows: [],
            selection: .constant([]),
            probe: nil,
            sourceIndex: 50004
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        coordinator.requestGeneration = 7
        coordinator.pendingPageGenerations[3] = 7
        coordinator.pendingPageTokens[3] = 11

        #expect(!coordinator.finishPageRequest(page: 3, generation: 6))
        #expect(coordinator.pendingPageGenerations[3] == 7)
        #expect(!coordinator.finishPageRequest(
            page: 3,
            generation: 7,
            token: 10
        ))
        #expect(coordinator.pendingPageTokens[3] == 11)
        #expect(coordinator.finishPageRequest(
            page: 3,
            generation: 7,
            token: 11
        ))
        #expect(coordinator.pendingPageGenerations[3] == nil)
        #expect(coordinator.pendingPageTokens[3] == nil)
    }

    @Test("Content versions advance only for their owning source")
    func contentVersionsAdvanceOnlyForTheirSource() {
        let store = LibraryStore()
        let track = makeTracks(count: 1)[0]
        let initialTracks = store.tracksVersion
        let initialFavorites = store.favoriteTracksVersion
        let initialBrowser = store.browserTracksVersion
        let initialPlaylist = store.selectedPlaylistTracksVersion
        let initialSearch = store.catalogSearchTracksVersion

        #expect(store.replaceTracksContent(with: [track]))
        #expect(store.tracksVersion == initialTracks.advanced())
        #expect(store.favoriteTracksVersion == initialFavorites)
        #expect(store.browserTracksVersion == initialBrowser)
        #expect(store.selectedPlaylistTracksVersion == initialPlaylist)
        #expect(store.catalogSearchTracksVersion == initialSearch)

        #expect(!store.replaceTracksContent(with: [track]))
        #expect(store.tracksVersion == initialTracks.advanced())

        var nonTrackSearchPage = CatalogSearchResults.empty
        nonTrackSearchPage.artistCursor = .offset(40)
        store.replaceCatalogSearchResults(with: nonTrackSearchPage)
        #expect(store.catalogSearchTracksVersion == initialSearch)

        #expect(store.replaceBrowserTracksContent(with: [track]))
        #expect(store.browserTracksVersion == initialBrowser.advanced())
        #expect(store.tracksVersion == initialTracks.advanced())
    }
}

private enum TrackTableSelectionTestError: Error {
    case missingTrackConfiguration
}

private final class TrackTableFocusProbeView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

private final class TrackTableFocusWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }
}

@MainActor
private struct VirtualReplacementVerificationContext {
    let initialRows: [LibraryTrackProjection]
    let selectedTrack: LibraryTrackProjection
    let source: MutableTrackWindowSource
    let window: LibraryTrackWindow
    let contentVersion: TrackTableContentVersion
    let selection: Binding<Set<UUID>>
    let core: TrackTableCore
    let coordinator: TrackTableCore.Coordinator
    let tableView: RecordingTrackTableView
    let visibleRows: IndexSet
}
