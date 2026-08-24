import AppKit
@testable import Cadence
import Foundation
import SwiftData
import SwiftUI
import Testing

@MainActor
struct AllTracksPerformanceTests {
    let presentationModel = CadenceAppModel.testFixture()

    @Test("The track window evicts least-recently-used pages")
    func boundedTrackWindow() {
        var cache = TrackPageWindow<Int>(pageCapacity: 3)

        cache.insert([0, 1], page: 0)
        cache.insert([2, 3], page: 1)
        cache.insert([4, 5], page: 2)
        #expect(cache.item(at: 0, pageSize: 2) == 0)

        cache.insert([6, 7], page: 3)

        #expect(cache.cachedPageCount == 3)
        #expect(cache.item(at: 0, pageSize: 2) == 0)
        #expect(cache.item(at: 2, pageSize: 2) == nil)
        #expect(cache.item(at: 6, pageSize: 2) == 6)
    }

    @Test("A viewport requests each page once until that page completes")
    func coalescedViewportRequests() {
        var requests = TrackViewportPageRequests(pageSize: 200)

        #expect(requests.beginRequest(containing: 399) == 1)
        #expect(requests.beginRequest(containing: 398) == nil)
        requests.finishRequest(page: 1)
        #expect(requests.beginRequest(containing: 399) == nil)

        requests.invalidate()
        #expect(requests.beginRequest(containing: 399) == 1)
    }

    @Test("Viewport prefetch stays a fixed distance ahead of visible rows")
    func boundedPrefetchRange() {
        let range = TrackViewportPrefetch.range(
            visibleRows: 9 ... 27,
            totalCount: 1_000_000,
            pageSize: 200,
            prefetchPages: 1
        )

        #expect(range == 0 ... 399)
    }

    @Test("Viewport prefetch follows the current scroll direction")
    func directionalPrefetchPages() {
        #expect(
            TrackViewportPrefetch.pages(
                around: 8,
                pageCount: 20,
                prefetchPages: 2,
                direction: .before
            ) == [7, 6]
        )
        #expect(
            TrackViewportPrefetch.pages(
                around: 8,
                pageCount: 20,
                prefetchPages: 2,
                direction: .after
            ) == [9, 10]
        )
        #expect(
            TrackViewportPrefetch.pages(
                around: 0,
                pageCount: 20,
                prefetchPages: 2,
                direction: .before
            ).isEmpty
        )
    }

    @Test("Track rows request artwork near their rendered pixel size")
    func rowArtworkBudget() {
        #expect(ArtworkAssetVariant.trackRow.maximumPixelDimension == 128)
        #expect(ArtworkAssetVariant.thumbnail.maximumPixelDimension == 512)
    }

    @Test("A million-track catalog loads a constant number of viewport pages")
    func millionTrackWindow() async {
        let counter = TrackWindowLoadCounter()
        let window = LibraryTrackWindow(
            pageSize: 64,
            pageCapacity: 3,
            prefetchPages: 1
        ) { _, offset, limit in
            await counter.record(offset: offset, limit: limit)
            return []
        }

        await window.configure(
            totalCount: 1_000_000,
            query: .allTracks,
            contentVersion: TrackTableContentVersion(
                sourceID: deterministicUUID(60000),
                generation: 0
            )
        )
        await window.load(page: 10000)

        #expect(window.pageCount == 15625)
        #expect(await counter.requests == [0, 64, 640_000, 640_064])
    }

    @Test("Loading upward does not immediately evict and reload the next page")
    func upwardTrackWindow() async {
        let counter = TrackWindowLoadCounter()
        let window = LibraryTrackWindow(
            pageSize: 64,
            pageCapacity: 4,
            prefetchPages: 1
        ) { _, offset, limit in
            await counter.record(offset: offset, limit: limit)
            return []
        }

        await window.configure(
            totalCount: 1000,
            query: .allTracks,
            contentVersion: TrackTableContentVersion(
                sourceID: deterministicUUID(60001),
                generation: 0
            )
        )
        await window.load(page: 8, prefetchDirection: .before)

        #expect(await counter.requests == [0, 64, 512, 448])
    }

    @Test("The first viewport reports loading and becomes ready on first open")
    func firstViewportLifecycle() async {
        let track = makeTrack(title: "First Track")
        let window = LibraryTrackWindow(
            pageSize: 64,
            pageCapacity: 3,
            prefetchPages: 0
        ) { _, offset, _ in
            offset == 0 ? [track] : []
        }

        #expect(window.firstPageState == .idle)
        await window.configure(
            totalCount: 1,
            query: .allTracks,
            contentVersion: TrackTableContentVersion(
                sourceID: deterministicUUID(60002),
                generation: 0
            )
        )

        #expect(window.firstPageState == .ready)
        #expect(window.track(at: 0) == track)
    }

    @Test("A superseded semantic refresh cannot publish its older version")
    func supersededSemanticRefreshCannotRegressContentVersion() async {
        let initial = makeTrack(title: "Initial")
        let stale = replacingTitle(initial, with: "Stale")
        let newest = replacingTitle(initial, with: "Newest")
        let source = OverlappingTrackWindowSource(
            initialRows: [initial],
            suspendedRows: [stale],
            newestRows: [newest]
        )
        let window = LibraryTrackWindow(
            pageSize: 1,
            pageCapacity: 1,
            prefetchPages: 0
        ) { _, offset, limit in
            try await source.rows(offset: offset, limit: limit)
        }
        let initialVersion = TrackTableContentVersion(
            sourceID: deterministicUUID(60003),
            generation: 0
        )
        let staleVersion = initialVersion.advanced()
        let newestVersion = staleVersion.advanced()
        await window.configure(
            totalCount: 1,
            query: .allTracks,
            contentVersion: initialVersion
        )

        let staleRefresh = Task { @MainActor in
            await window.configure(
                totalCount: 1,
                query: .allTracks,
                contentVersion: staleVersion
            )
        }
        await source.waitUntilSuspended()
        let newestRefresh = Task { @MainActor in
            await window.configure(
                totalCount: 1,
                query: .allTracks,
                contentVersion: newestVersion
            )
        }
        await newestRefresh.value
        await source.resumeSuspendedRequest()
        await staleRefresh.value

        #expect(window.contentVersion == newestVersion)
        #expect(window.track(at: 0) == newest)
    }
}

extension AllTracksPerformanceTests {
    @Test("A same-count track rename refreshes the configured virtual page once")
    func sameCountTrackRenameRefreshesVirtualPage() async throws {
        let fixture = try VirtualTrackMutationFixture()
        defer { fixture.remove() }
        let store = LibraryStore(
            container: fixture.container,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let window = try #require(store.allTracksWindow)
        await configureAllTracksWindow(window, store: store)
        let revisionBeforeRename = window.revision

        _ = try await store.renameTrack(
            id: fixture.trackID,
            title: "Renamed Track"
        )
        await configureAllTracksWindow(window, store: store)

        #expect(window.totalCount == 1)
        #expect(window.query == .allTracks)
        #expect(window.track(at: 0)?.title == "Renamed Track")
        #expect(window.revision == revisionBeforeRename + 1)
    }

    @Test("A same-count track artwork replacement refreshes the virtual page once")
    func sameCountTrackArtworkRefreshesVirtualPage() async throws {
        let fixture = try VirtualTrackMutationFixture()
        defer { fixture.remove() }
        let store = LibraryStore(
            container: fixture.container,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let window = try #require(store.allTracksWindow)
        await configureAllTracksWindow(window, store: store)
        let revisionBeforeArtwork = window.revision

        try await store.setArtwork(
            fixture.artworkRequest(
                ownerKind: .track,
                ownerID: fixture.trackID
            ),
            location: fixture.location
        )
        await configureAllTracksWindow(window, store: store)

        #expect(window.totalCount == 1)
        #expect(window.track(at: 0)?.artworkID != nil)
        #expect(window.revision == revisionBeforeArtwork + 1)
    }

    @Test("An unrelated catalog artwork update performs no virtual track work")
    func unrelatedArtworkDoesNotRefreshVirtualPage() async throws {
        let fixture = try VirtualTrackMutationFixture()
        defer { fixture.remove() }
        let store = LibraryStore(
            container: fixture.container,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let window = try #require(store.allTracksWindow)
        await configureAllTracksWindow(window, store: store)
        let trackBeforeArtwork = try #require(window.track(at: 0))
        let revisionBeforeArtwork = window.revision

        try await store.setArtwork(
            fixture.artworkRequest(
                ownerKind: .artist,
                ownerID: fixture.artistID
            ),
            location: fixture.location
        )
        await configureAllTracksWindow(window, store: store)

        #expect(window.track(at: 0) == trackBeforeArtwork)
        #expect(window.revision == revisionBeforeArtwork)
    }

    @Test("A zero-to-positive table transition requires a full reload")
    func firstPresentationRefreshPolicy() {
        let snapshot = makeSnapshot(
            rows: [makeTrack(title: "First")],
            version: TrackTableContentVersion(
                sourceID: deterministicUUID(100),
                generation: 0
            )
        )
        let plan = TrackTableUpdatePlanner.plan(
            previous: nil,
            source: .materialized(snapshot),
            selection: [],
            presentation: presentation,
            visibleRows: []
        )

        #expect(plan.reload == .all)
        #expect(plan.restoresSelection)
    }

    @Test("A favorite change reloads visible rows without rebuilding the table")
    func sameCountMutationRefreshPolicy() {
        let before = makeTrack(title: "Signal")
        let after = LibraryTrackProjection(
            id: before.id,
            title: before.title,
            artistID: before.artistID,
            artist: before.artist,
            albumID: before.albumID,
            album: before.album,
            duration: before.duration,
            year: before.year,
            codec: before.codec,
            sampleRate: before.sampleRate,
            channelCount: before.channelCount,
            bitDepth: before.bitDepth,
            isFavorite: true,
            isExplicit: before.isExplicit,
            customArtworkID: before.customArtworkID,
            artworkID: before.artworkID,
            relativeMediaPath: before.relativeMediaPath,
            lastPlayedAt: before.lastPlayedAt,
            hasSynchronizedLyrics: before.hasSynchronizedLyrics
        )

        let version = TrackTableContentVersion(
            sourceID: deterministicUUID(101),
            generation: 0
        )
        let oldSnapshot = makeSnapshot(rows: [before], version: version)
        let newSnapshot = makeSnapshot(
            rows: [after],
            version: version.advanced()
        )
        let previous = TrackTableRenderedState(
            source: .materialized(oldSnapshot),
            selection: [],
            presentation: presentation
        )
        let probe = TrackTableWorkProbe()
        let plan = TrackTableUpdatePlanner.plan(
            previous: previous,
            source: .materialized(newSnapshot),
            selection: [],
            presentation: presentation,
            visibleRows: [],
            probe: probe
        )

        #expect(plan.reload == .rows(IndexSet(integer: 0)))
        #expect(probe.rowComparisons == 1)
    }

    @Test("Identical materialized updates perform no row work")
    func unchangedUpdateDoesNoWork() {
        for count in [1000, 10000] {
            let tracks = makeTracks(count: count)
            let probe = TrackTableWorkProbe()
            let cache = TrackTableProjectionCache(probe: probe)
            let version = TrackTableContentVersion(
                sourceID: deterministicUUID(count + 20000),
                generation: 0
            )
            let snapshot = cache.resolve(
                rows: tracks,
                contentVersion: version,
                sortDescriptor: titleSort,
                repositoryOrdered: false
            )
            var renderedState = TrackTableRenderedState(
                source: .materialized(snapshot),
                selection: [],
                presentation: presentation
            )
            probe.reset()

            for _ in 0 ..< 100 {
                let current = cache.resolve(
                    rows: tracks,
                    contentVersion: version,
                    sortDescriptor: titleSort,
                    repositoryOrdered: false
                )
                let plan = TrackTableUpdatePlanner.plan(
                    previous: renderedState,
                    source: .materialized(current),
                    selection: [],
                    presentation: presentation,
                    visibleRows: [],
                    probe: probe
                )
                #expect(plan == TrackTableUpdatePlan(
                    reload: .none,
                    reconcilesVirtualSelection: false,
                    restoresSelection: false,
                    requestsViewport: false,
                    resetsEndPaging: false
                ))
                renderedState = TrackTableRenderedState(
                    source: .materialized(current),
                    selection: [],
                    presentation: presentation
                )
            }

            #expect(probe.sortPasses == 0)
            #expect(probe.rowComparisons == 0)
            #expect(probe.fullReloads == 0)
            #expect(probe.reloadBatches == 0)
            #expect(probe.reloadedRows == 0)
            #expect(probe.selectionRestores == 0)
            #expect(probe.viewportRequests == 0)
            #expect(probe.hostConfigurations == 0)
        }
    }

    @Test("A stable-ID mutation compares once and reloads one row")
    func stableIdentityMutationReloadsOneRow() {
        for count in [1000, 10000] {
            let rows = makeTracks(count: count)
            let changedIndex = count / 2
            var changedRows = rows
            changedRows[changedIndex] = togglingFavorite(rows[changedIndex])
            let probe = TrackTableWorkProbe()
            let cache = TrackTableProjectionCache(probe: probe)
            let version = TrackTableContentVersion(
                sourceID: deterministicUUID(count + 40000),
                generation: 0
            )
            let before = cache.resolve(
                rows: rows,
                contentVersion: version,
                sortDescriptor: titleSort,
                repositoryOrdered: false
            )
            let renderedState = TrackTableRenderedState(
                source: .materialized(before),
                selection: [],
                presentation: presentation
            )
            probe.reset()

            let after = cache.resolve(
                rows: changedRows,
                contentVersion: version.advanced(),
                sortDescriptor: titleSort,
                repositoryOrdered: false
            )
            let plan = TrackTableUpdatePlanner.plan(
                previous: renderedState,
                source: .materialized(after),
                selection: [],
                presentation: presentation,
                visibleRows: IndexSet(integer: changedIndex),
                probe: probe
            )

            #expect(plan.reload == .rows(IndexSet(integer: changedIndex)))
            #expect(!plan.restoresSelection)
            #expect(!plan.requestsViewport)
            #expect(!plan.resetsEndPaging)
            #expect(probe.sortPasses == 1)
            #expect(probe.rowComparisons == count)
            #expect(probe.fullReloads == 0)
        }
    }

    @Test("An order mutation moves and reloads only the changed row")
    func orderMutationUsesIncrementalMove() {
        let rows = makeTracks(count: 1000)
        var changedRows = rows
        changedRows[0] = replacingTitle(
            rows[0],
            with: "Track 99999"
        )
        let probe = TrackTableWorkProbe()
        let cache = TrackTableProjectionCache(probe: probe)
        let version = TrackTableContentVersion(
            sourceID: deterministicUUID(50000),
            generation: 0
        )
        let before = cache.resolve(
            rows: rows,
            contentVersion: version,
            sortDescriptor: titleSort,
            repositoryOrdered: false
        )
        let renderedState = TrackTableRenderedState(
            source: .materialized(before),
            selection: [],
            presentation: presentation
        )
        probe.reset()
        let after = cache.resolve(
            rows: changedRows,
            contentVersion: version.advanced(),
            sortDescriptor: titleSort,
            repositoryOrdered: false
        )

        let plan = TrackTableUpdatePlanner.plan(
            previous: renderedState,
            source: .materialized(after),
            selection: [],
            presentation: presentation,
            visibleRows: IndexSet(integersIn: 0 ..< 24),
            probe: probe
        )

        #expect(
            plan.reload == .changes(
                TrackTableChanges(
                    movedRows: [TrackTableMove(from: 0, to: 999)],
                    reloadedRows: IndexSet(integer: 999)
                )
            )
        )
        #expect(plan.resetsEndPaging)
        #expect(probe.sortPasses == 1)
    }

    @Test("Projection sorting is memoized by semantic key")
    func projectionCacheSortsOncePerSemanticKey() {
        let rows = makeTracks(count: 1000)
        let probe = TrackTableWorkProbe()
        let cache = TrackTableProjectionCache(probe: probe)
        let version = TrackTableContentVersion(
            sourceID: deterministicUUID(50001),
            generation: 0
        )
        let albumSort = TrackTableSortDescriptor(
            field: .album,
            direction: .ascending
        )

        _ = cache.resolve(
            rows: rows,
            contentVersion: version,
            sortDescriptor: titleSort,
            repositoryOrdered: false
        )
        _ = cache.resolve(
            rows: rows,
            contentVersion: version,
            sortDescriptor: titleSort,
            repositoryOrdered: false
        )
        #expect(probe.sortPasses == 1)

        _ = cache.resolve(
            rows: rows,
            contentVersion: version,
            sortDescriptor: albumSort,
            repositoryOrdered: false
        )
        #expect(probe.sortPasses == 2)

        _ = cache.resolve(
            rows: rows,
            contentVersion: version.advanced(),
            sortDescriptor: albumSort,
            repositoryOrdered: false
        )
        #expect(probe.sortPasses == 3)

        let repositoryProbe = TrackTableWorkProbe()
        let repositoryCache = TrackTableProjectionCache(
            probe: repositoryProbe
        )
        _ = repositoryCache.resolve(
            rows: rows,
            contentVersion: version,
            sortDescriptor: titleSort,
            repositoryOrdered: true
        )
        _ = repositoryCache.resolve(
            rows: rows,
            contentVersion: version.advanced(),
            sortDescriptor: albumSort,
            repositoryOrdered: true
        )
        #expect(repositoryProbe.sortPasses == 0)
    }
}
