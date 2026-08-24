import AppKit
@testable import Cadence
import Foundation
import SwiftData
import SwiftUI
import Testing

extension AllTracksPerformanceTests {
    @Test(
        "Visible hosting rows share one live queue owner without full projections"
    )
    func visibleRowsShareOneLiveQueueIDProvider() throws {
        let rows = makeTracks(count: 10000)
        let core = makeCore(
            rows: rows,
            selection: .constant([]),
            probe: nil,
            sourceIndex: 50005
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

        var cells: [TrackTableHostingCell] = []
        var configurations: [TrackTableRowConfiguration] = []
        for row in 0 ..< 24 {
            let cell = try #require(
                coordinator.tableView(
                    tableView,
                    viewFor: column,
                    row: row
                ) as? TrackTableHostingCell
            )
            guard case let .track(configuration) = cell.hostState.content else {
                Issue.record("Expected a configured track host at row \(row)")
                continue
            }
            cells.append(cell)
            configurations.append(configuration)
        }

        let retainedFullQueueCounts: [Int] = configurations.flatMap { configuration in
            Mirror(reflecting: configuration).children.compactMap { child in
                guard
                    let queue = child.value as? [LibraryTrackProjection],
                    queue.count > 1
                else {
                    return nil
                }
                return queue.count
            }
        }
        let queueOwners = configurations.map(\.queueIDProvider)

        #expect(configurations.count == 24)
        #expect(retainedFullQueueCounts.isEmpty)
        #expect(queueOwners.count == 24)
        #expect(Set(queueOwners.map(ObjectIdentifier.init)).count == 1)

        let queueOwner = try #require(queueOwners.first)
        let initialSnapshot = try #require(core.snapshot)
        let visibleRows = IndexSet(integersIn: 0 ..< 24)
        coordinator.renderedState = TrackTableRenderedState(
            source: .materialized(initialSnapshot),
            selection: [],
            presentation: core.presentation
        )
        tableView.reloadHandler = { rowIndexes in
            for row in rowIndexes {
                tableView.reusableViews.append(cells[row])
                _ = coordinator.tableView(
                    tableView,
                    viewFor: column,
                    row: row
                )
            }
        }

        verifyQueueOwnerUpdates(
            context: LiveQueueMutationContext(
                rows: rows,
                queueOwner: queueOwner,
                coordinator: coordinator,
                initialSnapshot: initialSnapshot,
                visibleRows: visibleRows
            )
        )
    }

    private func verifyQueueOwnerUpdates(
        context: LiveQueueMutationContext
    ) {
        var currentRows = context.rows
        var version = context.initialSnapshot.identity.contentVersion
        var retiredSnapshots: [WeakObjectBox] = []
        for mutationIndex in 0 ..< 24 {
            retiredSnapshots.append(WeakObjectBox(context.queueOwner.snapshot))
            currentRows[mutationIndex] = replacingTitle(
                currentRows[mutationIndex],
                with: "Mutation \(mutationIndex)"
            )
            version = version.advanced()
            let updatedCore = makeCore(
                rows: currentRows,
                selection: .constant([]),
                probe: nil,
                version: version
            )
            let source = context.coordinator.renderedSource(
                for: updatedCore,
                visibleRows: context.visibleRows
            )
            let plan = TrackTableUpdatePlanner.plan(
                previous: context.coordinator.renderedState,
                source: source,
                selection: [],
                presentation: updatedCore.presentation,
                visibleRows: context.visibleRows
            )
            context.coordinator.parent = updatedCore
            context.coordinator.apply(plan.reload)
            context.coordinator.renderedState = TrackTableRenderedState(
                source: source,
                selection: [],
                presentation: updatedCore.presentation
            )

            #expect(plan.reload == .rows(IndexSet(integer: mutationIndex)))
        }

        retiredSnapshots.append(WeakObjectBox(context.queueOwner.snapshot))
        let firstRow = currentRows.removeFirst()
        currentRows.append(firstRow)
        version = version.advanced()
        let reorderedCore = makeCore(
            rows: currentRows,
            selection: .constant([]),
            probe: nil,
            version: version
        )
        let reorderedSource = context.coordinator.renderedSource(
            for: reorderedCore,
            visibleRows: context.visibleRows
        )
        let reorderedPlan = TrackTableUpdatePlanner.plan(
            previous: context.coordinator.renderedState,
            source: reorderedSource,
            selection: [],
            presentation: reorderedCore.presentation,
            visibleRows: context.visibleRows
        )
        context.coordinator.parent = reorderedCore
        context.coordinator.apply(reorderedPlan.reload)

        let latestIDs = currentRows.map(\.id)
        let movingIDs: Set<UUID> = [latestIDs[1], latestIDs[3]]
        let dropOrder = context.queueOwner.reorderedIDs(
            moving: movingIDs,
            before: latestIDs[5]
        )
        #expect(
            reorderedPlan.reload == .changes(
                TrackTableChanges(
                    movedRows: [
                        TrackTableMove(from: 0, to: currentRows.count - 1),
                    ]
                )
            )
        )
        #expect(context.queueOwner.orderedIDs == latestIDs)
        #expect(
            Array(dropOrder.prefix(7)) == [
                latestIDs[0],
                latestIDs[2],
                latestIDs[4],
                latestIDs[1],
                latestIDs[3],
                latestIDs[5],
                latestIDs[6],
            ]
        )
        #expect(retiredSnapshots.allSatisfy { $0.value == nil })
    }

    @Test("A hosting cell installs its SwiftUI root once")
    func hostingCellKeepsOneRoot() {
        let probe = TrackTableWorkProbe()
        let cell = TrackTableHostingCell(probe: probe)
        let first = makeTracks(count: 2)[0]
        let second = makeTracks(count: 2)[1]
        let stateID = ObjectIdentifier(cell.hostState)

        cell.configure(.track(rowConfiguration(first, isSelected: false)))
        cell.configure(.track(rowConfiguration(first, isSelected: true)))
        #expect(cell.hostState.trackID == first.id)
        #expect(ObjectIdentifier(cell.hostState) == stateID)

        cell.configure(.track(rowConfiguration(second, isSelected: false)))

        #expect(probe.hostingRootInstalls == 1)
        #expect(probe.hostConfigurations == 3)
        #expect(cell.hostState.trackID == second.id)
        #expect(ObjectIdentifier(cell.hostState) == stateID)
    }

    @Test(
        "A reused hosting cell publishes artwork only for its current track",
        .appKitExclusive
    )
    func reusedHostingCellSuppressesStaleArtwork() async throws {
        let fixture = try ReusedArtworkCellFixture(tests: self)
        defer { fixture.finish() }

        await fixture.startFirstRequest()
        await fixture.publishSecondArtwork()
        await fixture.verifySelectionOnlyUpdate()
        await fixture.releaseStaleArtworkAndVerify()
    }
}

@MainActor
private struct LiveQueueMutationContext {
    let rows: [LibraryTrackProjection]
    let queueOwner: TrackTableQueueIDProvider
    let coordinator: TrackTableCore.Coordinator
    let initialSnapshot: TrackTableProjectionSnapshot
    let visibleRows: IndexSet
}

@MainActor
private final class ReusedArtworkCellFixture {
    let tests: AllTracksPerformanceTests
    let hostProbe: TrackTableWorkProbe
    let artworkProbe: ProductionArtworkWorkProbe
    let loader: SuspendedTrackArtworkLoader
    let artworkData: Data
    let firstArtworkID: UUID
    let secondArtworkID: UUID
    let first: LibraryTrackProjection
    let second: LibraryTrackProjection
    let cell: TrackTableHostingCell
    let hostStateID: ObjectIdentifier
    let window: NSWindow
    let artworkLoader:
        @MainActor @Sendable (UUID, ArtworkAssetVariant) async -> ArtworkAsset?

    private var taskStartsAfterSecondPublication = 0

    init(tests: AllTracksPerformanceTests) throws {
        let hostProbe = TrackTableWorkProbe()
        let artworkProbe = ProductionArtworkWorkProbe()
        let loader = SuspendedTrackArtworkLoader()
        let representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 1,
                pixelsHigh: 1,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let artworkData = try #require(
            representation.representation(using: .png, properties: [:])
        )
        let tracks = tests.makeTracks(count: 2)
        let firstArtworkID = tests.deterministicUUID(50007)
        let secondArtworkID = tests.deterministicUUID(50008)
        let cell = TrackTableHostingCell(
            frame: NSRect(x: 0, y: 0, width: 900, height: 58),
            probe: hostProbe
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 58),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.tests = tests
        self.hostProbe = hostProbe
        self.artworkProbe = artworkProbe
        self.loader = loader
        self.artworkData = artworkData
        self.firstArtworkID = firstArtworkID
        self.secondArtworkID = secondArtworkID
        first = tests.replacingArtworkID(
            tracks[0],
            with: firstArtworkID
        )
        second = tests.replacingArtworkID(
            tracks[1],
            with: secondArtworkID
        )
        self.cell = cell
        hostStateID = ObjectIdentifier(cell.hostState)
        self.window = window
        artworkLoader = { artworkID, variant in
            await loader.load(
                artworkID: artworkID,
                variant: variant
            )
        }

        window.isReleasedWhenClosed = false
        window.contentView = cell
        window.orderFront(nil)
    }

    func finish() {
        loader.releaseAll()
        window.orderOut(nil)
        window.close()
    }

    func startFirstRequest() async {
        configure(first, isSelected: false)
        for _ in 0 ..< 500 where !loader.hasStarted(firstArtworkID) {
            await Task.yield()
        }
        #expect(loader.hasStarted(firstArtworkID))
    }

    func publishSecondArtwork() async {
        configure(second, isSelected: false)
        for _ in 0 ..< 500 where !loader.hasStarted(secondArtworkID) {
            await Task.yield()
        }
        #expect(loader.hasStarted(secondArtworkID))

        loader.release(
            secondArtworkID,
            asset: ArtworkAsset(
                id: secondArtworkID,
                data: artworkData,
                variant: .trackRow
            )
        )
        for _ in 0 ..< 500
            where artworkProbe.publishedArtworkIDs != [secondArtworkID] {
            await Task.yield()
        }
        #expect(artworkProbe.publishedArtworkIDs == [secondArtworkID])
        taskStartsAfterSecondPublication = artworkProbe.taskStarts
    }

    func verifySelectionOnlyUpdate() async {
        configure(second, isSelected: true)
        for _ in 0 ..< 100 {
            await Task.yield()
        }
        #expect(artworkProbe.taskStarts == taskStartsAfterSecondPublication)
    }

    func releaseStaleArtworkAndVerify() async {
        loader.release(
            firstArtworkID,
            asset: ArtworkAsset(
                id: firstArtworkID,
                data: artworkData,
                variant: .trackRow
            )
        )
        for _ in 0 ..< 500
            where loader.observedCancellation(for: firstArtworkID) == nil {
            await Task.yield()
        }

        #expect(loader.observedCancellation(for: firstArtworkID) == true)
        #expect(artworkProbe.taskStarts == 2)
        #expect(artworkProbe.publishedArtworkIDs == [secondArtworkID])
        #expect(hostProbe.hostingRootInstalls == 1)
        #expect(hostProbe.hostConfigurations == 3)
        #expect(cell.hostState.trackID == second.id)
        #expect(ObjectIdentifier(cell.hostState) == hostStateID)
    }

    private func configure(
        _ track: LibraryTrackProjection,
        isSelected: Bool
    ) {
        cell.configure(
            .track(
                tests.rowConfiguration(
                    track,
                    isSelected: isSelected,
                    artworkLoader: artworkLoader,
                    artworkWorkProbe: artworkProbe
                )
            )
        )
        cell.layoutSubtreeIfNeeded()
    }
}
