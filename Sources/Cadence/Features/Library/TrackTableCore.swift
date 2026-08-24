import AppKit
import SwiftUI

struct TrackTableContentVersion: Hashable, Sendable {
    let sourceID: UUID
    let generation: UInt64

    func advanced() -> Self {
        precondition(generation < .max)
        return Self(
            sourceID: sourceID,
            generation: generation + 1
        )
    }
}

@MainActor
final class TrackTableContentClock {
    private let sourceID: UUID
    private var generation: UInt64 = 0

    init(sourceID: UUID = UUID()) {
        self.sourceID = sourceID
    }

    var version: TrackTableContentVersion {
        TrackTableContentVersion(
            sourceID: sourceID,
            generation: generation
        )
    }

    func advance() {
        generation = version.advanced().generation
    }
}

struct TrackTableProjectionIdentity: Hashable, Sendable {
    let contentVersion: TrackTableContentVersion
    let localSort: TrackTableSortDescriptor?
}

struct TrackTableProjectionSnapshot: Sendable {
    let identity: TrackTableProjectionIdentity
    let rows: [LibraryTrackProjection]
    let orderedIDs: [UUID]
    let indexByID: [UUID: Int]
}

@MainActor
final class TrackTableQueueIDSnapshot {
    let identity: TrackTableProjectionIdentity?
    let orderedIDs: [UUID]

    init(projection: TrackTableProjectionSnapshot?) {
        identity = projection?.identity
        orderedIDs = projection?.orderedIDs ?? []
    }
}

@MainActor
final class TrackTableQueueIDProvider {
    private(set) var snapshot: TrackTableQueueIDSnapshot

    init(snapshot: TrackTableProjectionSnapshot?) {
        self.snapshot = TrackTableQueueIDSnapshot(projection: snapshot)
    }

    var orderedIDs: [UUID] {
        snapshot.orderedIDs
    }

    func update(from projection: TrackTableProjectionSnapshot?) {
        guard snapshot.identity != projection?.identity else {
            return
        }
        snapshot = TrackTableQueueIDSnapshot(projection: projection)
    }

    func reorderedIDs(
        moving movingIDs: Set<UUID>,
        before targetID: UUID
    ) -> [UUID] {
        let movingInQueueOrder = orderedIDs.filter(movingIDs.contains)
        var reordered = orderedIDs.filter { !movingIDs.contains($0) }
        let targetIndex = reordered.firstIndex(of: targetID)
            ?? reordered.endIndex
        reordered.insert(contentsOf: movingInQueueOrder, at: targetIndex)
        return reordered
    }
}

@MainActor
final class TrackTableProjectionCache {
    private var cached: TrackTableProjectionSnapshot?
    private let probe: TrackTableWorkProbe?

    init(probe: TrackTableWorkProbe? = nil) {
        self.probe = probe
    }

    func resolve(
        rows: [LibraryTrackProjection],
        contentVersion: TrackTableContentVersion,
        sortDescriptor: TrackTableSortDescriptor,
        repositoryOrdered: Bool
    ) -> TrackTableProjectionSnapshot {
        let identity = TrackTableProjectionIdentity(
            contentVersion: contentVersion,
            localSort: repositoryOrdered ? nil : sortDescriptor
        )
        if let cached, cached.identity == identity {
            return cached
        }

        let projectedRows: [LibraryTrackProjection]
        if repositoryOrdered {
            projectedRows = rows
        } else {
            probe?.recordSortPass()
            projectedRows = sortDescriptor.sorted(rows)
        }
        var orderedIDs: [UUID] = []
        orderedIDs.reserveCapacity(projectedRows.count)
        var indexByID: [UUID: Int] = [:]
        indexByID.reserveCapacity(projectedRows.count)
        for (index, row) in projectedRows.enumerated() {
            orderedIDs.append(row.id)
            indexByID[row.id] = index
        }
        let snapshot = TrackTableProjectionSnapshot(
            identity: identity,
            rows: projectedRows,
            orderedIDs: orderedIDs,
            indexByID: indexByID
        )
        cached = snapshot
        return snapshot
    }
}

@MainActor
final class TrackTableWorkProbe {
    private(set) var appliedUpdates = 0
    private(set) var sortPasses = 0
    private(set) var rowComparisons = 0
    private(set) var fullReloads = 0
    private(set) var reloadBatches = 0
    private(set) var reloadedRows = 0
    private(set) var selectionRestores = 0
    private(set) var viewportRequests = 0
    private(set) var hostingRootInstalls = 0
    private(set) var hostConfigurations = 0
    private(set) var virtualStampComparisons = 0
    private(set) var virtualStampReads = 0
    private(set) var tableFrameWrites = 0
    private(set) var columnWidthWrites = 0
    private(set) var pageTaskStarts = 0
    private(set) var hostTrackIdentityChanges = 0
    private(set) var actionSelectionResolutions = 0
    private(set) var liveScrollPresentationChanges = 0
    private(set) var lightweightPresentationActivations = 0
    private(set) var nativeCellCreations = 0
    private(set) var nativeCellConfigurations = 0
    private(set) var nativeTrackIdentityChanges = 0
    private(set) var maximumNativeConfigurationNanoseconds: UInt64 = 0
    private(set) var displayProjectionBuilds = 0
    private(set) var displayProjectionCacheHits = 0
    private(set) var insertedRows = 0
    private(set) var removedRows = 0
    private(set) var movedRows = 0
    private(set) var nativeContentApplications = 0
    private(set) var nativeLayoutInvalidations = 0

    func reset() {
        appliedUpdates = 0
        sortPasses = 0
        rowComparisons = 0
        fullReloads = 0
        reloadBatches = 0
        reloadedRows = 0
        selectionRestores = 0
        viewportRequests = 0
        hostingRootInstalls = 0
        hostConfigurations = 0
        virtualStampComparisons = 0
        virtualStampReads = 0
        tableFrameWrites = 0
        columnWidthWrites = 0
        pageTaskStarts = 0
        hostTrackIdentityChanges = 0
        actionSelectionResolutions = 0
        liveScrollPresentationChanges = 0
        lightweightPresentationActivations = 0
        nativeCellCreations = 0
        nativeCellConfigurations = 0
        nativeTrackIdentityChanges = 0
        maximumNativeConfigurationNanoseconds = 0
        displayProjectionBuilds = 0
        displayProjectionCacheHits = 0
        insertedRows = 0
        removedRows = 0
        movedRows = 0
        nativeContentApplications = 0
        nativeLayoutInvalidations = 0
    }

    func recordAppliedUpdate() {
        appliedUpdates += 1
    }

    func recordSortPass() {
        sortPasses += 1
    }

    func recordRowComparison() {
        rowComparisons += 1
    }

    func recordFullReload() {
        fullReloads += 1
    }

    func recordReload(rows: Int) {
        reloadBatches += 1
        reloadedRows += rows
    }

    func recordSelectionRestore() {
        selectionRestores += 1
    }

    func recordViewportRequest() {
        viewportRequests += 1
    }

    func recordHostingRootInstall() {
        hostingRootInstalls += 1
    }

    func recordHostConfiguration() {
        hostConfigurations += 1
    }

    func recordVirtualStampComparison() {
        virtualStampComparisons += 1
    }

    func recordVirtualStampRead() {
        virtualStampReads += 1
    }

    func recordTableFrameWrite() {
        tableFrameWrites += 1
    }

    func recordColumnWidthWrite() {
        columnWidthWrites += 1
    }

    func recordPageTaskStart() {
        pageTaskStarts += 1
    }

    func recordHostTrackIdentityChange() {
        hostTrackIdentityChanges += 1
    }

    func recordActionSelectionResolution() {
        actionSelectionResolutions += 1
    }

    func recordLiveScrollPresentationChange(
        usesLightweightPresentation: Bool
    ) {
        liveScrollPresentationChanges += 1
        if usesLightweightPresentation {
            lightweightPresentationActivations += 1
        }
    }

    func recordNativeCellCreation() {
        nativeCellCreations += 1
    }

    func recordNativeCellConfiguration(
        durationNanoseconds: UInt64
    ) {
        nativeCellConfigurations += 1
        maximumNativeConfigurationNanoseconds = max(
            maximumNativeConfigurationNanoseconds,
            durationNanoseconds
        )
    }

    func recordNativeTrackIdentityChange() {
        nativeTrackIdentityChanges += 1
    }

    func recordDisplayProjectionBuild() {
        displayProjectionBuilds += 1
    }

    func recordDisplayProjectionCacheHit() {
        displayProjectionCacheHits += 1
    }

    func recordStructuralChanges(_ changes: TrackTableChanges) {
        insertedRows += changes.insertedRows.count
        removedRows += changes.removedRows.count
        movedRows += changes.movedRows.count
    }

    func recordNativeContentApplication() {
        nativeContentApplications += 1
    }

    func recordNativeLayoutInvalidation() {
        nativeLayoutInvalidations += 1
    }
}

struct TrackTableMove: Equatable, Sendable {
    let from: Int
    let to: Int
}

struct TrackTableChanges: Equatable, Sendable {
    var insertedRows: IndexSet
    var removedRows: IndexSet
    var movedRows: [TrackTableMove]
    var reloadedRows: IndexSet

    init(
        insertedRows: IndexSet = [],
        removedRows: IndexSet = [],
        movedRows: [TrackTableMove] = [],
        reloadedRows: IndexSet = []
    ) {
        self.insertedRows = insertedRows
        self.removedRows = removedRows
        self.movedRows = movedRows
        self.reloadedRows = reloadedRows
    }
}

enum TrackTableReload: Equatable {
    case none
    case all
    case rows(IndexSet)
    case changes(TrackTableChanges)
}

struct TrackTableUpdatePlan: Equatable {
    let reload: TrackTableReload
    let reconcilesVirtualSelection: Bool
    let restoresSelection: Bool
    let requestsViewport: Bool
    let resetsEndPaging: Bool
}

struct TrackTablePresentationKey: Equatable {
    let modelID: ObjectIdentifier
    let context: TrackTableContext
    let columns: [TrackTableColumn]
    let widths: TrackTableResolvedWidths
    let playlistID: UUID?
    let queueSource: PlaybackQueueSource?
    let canReorder: Bool
    let renderer: TrackTableRenderer
    let currentTrackID: UUID?
    let isCurrentTrackPlaying: Bool

    init(
        modelID: ObjectIdentifier,
        context: TrackTableContext,
        columns: [TrackTableColumn],
        widths: TrackTableResolvedWidths,
        playlistID: UUID?,
        queueSource: PlaybackQueueSource?,
        canReorder: Bool,
        renderer: TrackTableRenderer = .native,
        currentTrackID: UUID? = nil,
        isCurrentTrackPlaying: Bool = false
    ) {
        self.modelID = modelID
        self.context = context
        self.columns = columns
        self.widths = widths
        self.playlistID = playlistID
        self.queueSource = queueSource
        self.canReorder = canReorder
        self.renderer = renderer
        self.currentTrackID = currentTrackID
        self.isCurrentTrackPlaying = isCurrentTrackPlaying
    }
}

enum TrackTableRenderer: Equatable, Sendable {
    case native
    case hosted
}

struct TrackTableVirtualIdentity: Equatable {
    let windowID: ObjectIdentifier
    let query: LibraryTrackQuery
    let totalCount: Int
    let contentVersion: TrackTableContentVersion?

    init(
        windowID: ObjectIdentifier,
        query: LibraryTrackQuery,
        totalCount: Int,
        contentVersion: TrackTableContentVersion? = nil
    ) {
        self.windowID = windowID
        self.query = query
        self.totalCount = totalCount
        self.contentVersion = contentVersion
    }
}

enum TrackTableRowStamp: Equatable {
    case placeholder
    case track(LibraryTrackProjection)
}

enum TrackTableRenderedSource {
    case materialized(TrackTableProjectionSnapshot)
    case virtual(
        identity: TrackTableVirtualIdentity,
        revision: Int,
        stamps: [Int: TrackTableRowStamp]
    )
}

struct TrackTableRenderedState {
    var source: TrackTableRenderedSource
    var selection: Set<UUID>
    let presentation: TrackTablePresentationKey
}

@MainActor
enum TrackTableUpdatePlanner {
    // Keeping the planner as one decision tree makes mutually exclusive update modes explicit.
    // swiftlint:disable:next function_body_length
    static func plan(
        previous: TrackTableRenderedState?,
        source: TrackTableRenderedSource,
        selection: Set<UUID>,
        presentation: TrackTablePresentationKey,
        visibleRows: IndexSet,
        probe: TrackTableWorkProbe? = nil
    ) -> TrackTableUpdatePlan {
        guard let previous else {
            return TrackTableUpdatePlan(
                reload: .all,
                reconcilesVirtualSelection: false,
                restoresSelection: true,
                requestsViewport: true,
                resetsEndPaging: true
            )
        }

        var rows = IndexSet()
        var reloadsAll = false
        var reconcilesVirtualSelection = false
        var requestsViewport = false
        var resetsEndPaging = false
        var changes = TrackTableChanges()

        switch (previous.source, source) {
        case let (.materialized(old), .materialized(current)):
            let isCompatibleSource = old.identity.contentVersion.sourceID
                == current.identity.contentVersion.sourceID
                && old.identity.localSort == current.identity.localSort
            if !isCompatibleSource {
                reloadsAll = true
                resetsEndPaging = true
            } else if old.identity != current.identity {
                planMaterializedChanges(
                    from: old,
                    to: current,
                    rows: &rows,
                    changes: &changes,
                    reloadsAll: &reloadsAll,
                    probe: probe
                )
                resetsEndPaging = old.rows.count != current.rows.count
                    || !changes.movedRows.isEmpty
            }
        case let (
            .virtual(oldIdentity, oldRevision, oldStamps),
            .virtual(currentIdentity, currentRevision, currentStamps)
        ):
            let sameVirtualSource = oldIdentity.windowID
                == currentIdentity.windowID
                && oldIdentity.query == currentIdentity.query
                && oldIdentity.totalCount == currentIdentity.totalCount
                && oldIdentity.contentVersion?.sourceID
                == currentIdentity.contentVersion?.sourceID
            if !sameVirtualSource {
                reloadsAll = true
                requestsViewport = true
                resetsEndPaging = true
            } else if oldIdentity != currentIdentity
                || oldRevision != currentRevision {
                requestsViewport = true
                if oldIdentity.contentVersion
                    != currentIdentity.contentVersion {
                    reconcilesVirtualSelection = true
                    resetsEndPaging = true
                }
                for index in visibleRows {
                    probe?.recordVirtualStampComparison()
                    let oldStamp = oldStamps[index]
                    let currentStamp = currentStamps[index]
                    if rowIdentityChanged(
                        from: oldStamp,
                        to: currentStamp
                    ) {
                        reloadsAll = true
                        resetsEndPaging = true
                        break
                    }
                    if oldStamp != currentStamp {
                        rows.insert(index)
                    }
                }
            }
        case (.materialized, .virtual), (.virtual, .materialized):
            reloadsAll = true
            requestsViewport = true
            resetsEndPaging = true
        }

        if !reloadsAll {
            rows.formUnion(
                supplementalReloadRows(
                    previous: previous,
                    source: source,
                    selection: selection,
                    presentation: presentation,
                    visibleRows: visibleRows
                )
            )
        }
        changes.reloadedRows.formUnion(rows)
        return TrackTableUpdatePlan(
            reload: reload(
                for: rows,
                changes: changes,
                reloadsAll: reloadsAll
            ),
            reconcilesVirtualSelection: reconcilesVirtualSelection,
            restoresSelection: reloadsAll
                || reconcilesVirtualSelection
                || previous.selection != selection,
            requestsViewport: requestsViewport,
            resetsEndPaging: resetsEndPaging
        )
    }

    private static func supplementalReloadRows(
        previous: TrackTableRenderedState,
        source: TrackTableRenderedSource,
        selection: Set<UUID>,
        presentation: TrackTablePresentationKey,
        visibleRows: IndexSet
    ) -> IndexSet {
        var rows = IndexSet()
        if previous.selection != selection {
            rows.formUnion(
                indexes(
                    for: previous.selection.union(selection),
                    source: source
                )
            )
        }
        if previous.presentation != presentation {
            rows.formUnion(visibleRows)
        }
        return rows
    }

    private static func reload(
        for rows: IndexSet,
        changes: TrackTableChanges,
        reloadsAll: Bool
    ) -> TrackTableReload {
        if reloadsAll {
            .all
        } else if !changes.insertedRows.isEmpty
            || !changes.removedRows.isEmpty
            || !changes.movedRows.isEmpty {
            .changes(changes)
        } else if rows.isEmpty {
            .none
        } else {
            .rows(rows)
        }
    }

    private static func planMaterializedChanges(
        from old: TrackTableProjectionSnapshot,
        to current: TrackTableProjectionSnapshot,
        rows: inout IndexSet,
        changes: inout TrackTableChanges,
        reloadsAll: inout Bool,
        probe: TrackTableWorkProbe?
    ) {
        let oldIDs = old.orderedIDs
        let currentIDs = current.orderedIDs

        if oldIDs == currentIDs {
            compareMaterializedContent(
                from: old,
                to: current,
                rows: &rows,
                probe: probe
            )
            return
        }

        if currentIDs.count > oldIDs.count,
           currentIDs.prefix(oldIDs.count).elementsEqual(oldIDs) {
            changes.insertedRows = IndexSet(
                integersIn: oldIDs.count ..< currentIDs.count
            )
            compareMaterializedPrefix(
                oldRows: old.rows,
                currentRows: current.rows,
                count: oldIDs.count,
                rows: &rows,
                probe: probe
            )
            return
        }

        if oldIDs.count > currentIDs.count,
           oldIDs.prefix(currentIDs.count).elementsEqual(currentIDs) {
            changes.removedRows = IndexSet(
                integersIn: currentIDs.count ..< oldIDs.count
            )
            compareMaterializedPrefix(
                oldRows: old.rows,
                currentRows: current.rows,
                count: currentIDs.count,
                rows: &rows,
                probe: probe
            )
            return
        }

        if oldIDs.count == currentIDs.count,
           Set(oldIDs) == Set(currentIDs),
           let move = singleMove(from: oldIDs, to: currentIDs) {
            changes.movedRows = [move]
            for (index, track) in current.rows.enumerated() {
                probe?.recordRowComparison()
                guard let oldIndex = old.indexByID[track.id] else {
                    reloadsAll = true
                    return
                }
                if old.rows[oldIndex] != track {
                    rows.insert(index)
                }
            }
            return
        }

        reloadsAll = true
    }

    private static func compareMaterializedContent(
        from old: TrackTableProjectionSnapshot,
        to current: TrackTableProjectionSnapshot,
        rows: inout IndexSet,
        probe: TrackTableWorkProbe?
    ) {
        compareMaterializedPrefix(
            oldRows: old.rows,
            currentRows: current.rows,
            count: current.rows.count,
            rows: &rows,
            probe: probe
        )
    }

    private static func compareMaterializedPrefix(
        oldRows: [LibraryTrackProjection],
        currentRows: [LibraryTrackProjection],
        count: Int,
        rows: inout IndexSet,
        probe: TrackTableWorkProbe?
    ) {
        for index in 0 ..< count {
            probe?.recordRowComparison()
            if oldRows[index] != currentRows[index] {
                rows.insert(index)
            }
        }
    }

    private static func singleMove(
        from oldIDs: [UUID],
        to currentIDs: [UUID]
    ) -> TrackTableMove? {
        guard let firstMismatch = oldIDs.indices.first(
            where: { oldIDs[$0] != currentIDs[$0] }
        ) else {
            return nil
        }

        if let destination = currentIDs.firstIndex(of: oldIDs[firstMismatch]),
           moving(oldIDs, from: firstMismatch, to: destination) == currentIDs {
            return TrackTableMove(from: firstMismatch, to: destination)
        }
        if let source = oldIDs.firstIndex(of: currentIDs[firstMismatch]),
           moving(oldIDs, from: source, to: firstMismatch) == currentIDs {
            return TrackTableMove(from: source, to: firstMismatch)
        }
        return nil
    }

    private static func moving<T: Equatable>(
        _ values: [T],
        from source: Int,
        to destination: Int
    ) -> [T] {
        var result = values
        let value = result.remove(at: source)
        result.insert(value, at: destination)
        return result
    }

    private static func rowIdentityChanged(
        from oldStamp: TrackTableRowStamp?,
        to currentStamp: TrackTableRowStamp?
    ) -> Bool {
        guard
            case let .track(oldTrack) = oldStamp,
            case let .track(currentTrack) = currentStamp
        else {
            return false
        }
        return oldTrack.id != currentTrack.id
    }

    private static func indexes(
        for trackIDs: Set<UUID>,
        source: TrackTableRenderedSource
    ) -> IndexSet {
        switch source {
        case let .materialized(snapshot):
            IndexSet(trackIDs.compactMap { snapshot.indexByID[$0] })
        case let .virtual(_, _, stamps):
            IndexSet(
                stamps.compactMap { index, stamp in
                    guard case let .track(track) = stamp,
                          trackIDs.contains(track.id) else {
                        return nil
                    }
                    return index
                }
            )
        }
    }
}

struct TrackTableCore: NSViewRepresentable {
    let model: CadenceAppModel
    let context: TrackTableContext
    let snapshot: TrackTableProjectionSnapshot?
    let virtualWindow: LibraryTrackWindow?
    let columns: [TrackTableColumn]
    let widths: TrackTableResolvedWidths
    let playlistID: UUID?
    let queueSource: PlaybackQueueSource?
    let reorderAction: (([UUID]) -> Void)?
    let onReachEnd: (() async -> Void)?
    var refreshAction: CadenceRefreshAction?
    var renderer: TrackTableRenderer = .native
    var currentTrackID: UUID?
    var isCurrentTrackPlaying = false
    var workProbe: TrackTableWorkProbe?
    @Binding var selection: Set<UUID>

    var tracks: [LibraryTrackProjection] {
        snapshot?.rows ?? []
    }

    var totalCount: Int {
        virtualWindow?.totalCount ?? tracks.count
    }

    var presentation: TrackTablePresentationKey {
        TrackTablePresentationKey(
            modelID: ObjectIdentifier(model),
            context: context,
            columns: columns,
            widths: widths,
            playlistID: playlistID,
            queueSource: queueSource,
            canReorder: reorderAction != nil,
            renderer: renderer,
            currentTrackID: currentTrackID,
            isCurrentTrackPlaying: isCurrentTrackPlaying
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = TrackTableView()
        tableView.headerView = nil
        tableView.style = .plain
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
        tableView.onFocusChange = { [weak coordinator = context.coordinator] in
            coordinator?.tableFocusDidChange()
        }
        tableView.registerForDraggedTypes([.string])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setDraggingSourceOperationMask([], forLocal: false)

        let column = NSTableColumn(identifier: Coordinator.columnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.attach(
            tableView: tableView,
            scrollView: scrollView
        )
        context.coordinator.updateRefreshAffordance()
        return scrollView
    }

    func updateNSView(
        _ scrollView: NSScrollView,
        context: Context
    ) {
        applyUpdate(to: scrollView, coordinator: context.coordinator)
    }

    func applyUpdate(
        to scrollView: NSScrollView,
        coordinator: Coordinator
    ) {
        guard scrollView.documentView is NSTableView else {
            return
        }
        workProbe?.recordAppliedUpdate()
        let visibleRows = coordinator.visibleRowIndexes(
            totalCount: totalCount
        )
        let source = coordinator.renderedSource(
            for: self,
            visibleRows: visibleRows
        )
        let plan = TrackTableUpdatePlanner.plan(
            previous: coordinator.renderedState,
            source: source,
            selection: selection,
            presentation: presentation,
            visibleRows: visibleRows,
            probe: workProbe
        )
        if coordinator.renderedState?.selection != selection {
            coordinator.invalidateActionSelectionCache()
        }
        coordinator.parent = self
        coordinator.updateRefreshAffordance()
        coordinator.refreshAccessibilityPreferences()
        if plan.reconcilesVirtualSelection {
            coordinator.reconcileVirtualSelection()
        }
        coordinator.updateColumnWidth()
        if plan.resetsEndPaging {
            coordinator.resetPagingRequests()
        }
        coordinator.apply(plan.reload)
        if plan.restoresSelection {
            coordinator.restoreSelection()
        }
        if plan.requestsViewport {
            coordinator.requestVisibleRows()
        }
        coordinator.renderedState = TrackTableRenderedState(
            source: coordinator.committedSource(
                after: source,
                visibleRows: visibleRows
            ),
            selection: coordinator.parent.selection,
            presentation: presentation
        )
    }

    static func dismantleNSView(
        _: NSScrollView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }
}
