import AppKit
@testable import Cadence
import Foundation
import SwiftUI
import Testing

extension AllTracksPerformanceTests {
    @Test("A completed visible page keeps the next directional page prefetched")
    func completedVisiblePageKeepsNextPagePrefetched() async throws {
        let rows = makeTracks(count: 120)
        let source = SuspendedAttemptTrackWindowSource(
            rows: rows,
            suspendedOffset: 24,
            suspendedAttempt: 1
        )
        let window = LibraryTrackWindow(
            pageSize: 12,
            pageCapacity: 4,
            prefetchPages: 1
        ) { _, offset, limit in
            await source.rows(offset: offset, limit: limit)
        }
        await window.configure(
            totalCount: rows.count,
            query: .allTracks,
            contentVersion: TrackTableContentVersion(
                sourceID: deterministicUUID(81003),
                generation: 0
            )
        )
        let fixture = ViewportCoordinatorFixture(
            window: window,
            tests: self,
            visibleRows: NSRange(location: 12, length: 12)
        )
        defer {
            source.releaseAll()
            fixture.detach()
        }

        fixture.coordinator.visibleBoundsChanged()

        let nextPageTask = try #require(fixture.coordinator.pendingPages[2])
        await source.waitUntilStarted(offset: 24, attempt: 1)
        #expect(!nextPageTask.isCancelled)
        source.release(offset: 24, attempt: 1)
        await nextPageTask.value
    }

    @Test("A stable viewport retains prefetch until scroll direction reverses")
    func stableViewportRetainsPrefetchUntilDirectionReverses() async throws {
        let rows = makeTracks(count: 120)
        let source = SuspendedAttemptTrackWindowSource(
            rows: rows,
            suspendedOffset: 36,
            suspendedAttempt: 1
        )
        let window = LibraryTrackWindow(
            pageSize: 12,
            pageCapacity: 4,
            prefetchPages: 1
        ) { _, offset, limit in
            await source.rows(offset: offset, limit: limit)
        }
        await window.configure(
            totalCount: rows.count,
            query: .allTracks,
            contentVersion: TrackTableContentVersion(
                sourceID: deterministicUUID(81004),
                generation: 0
            )
        )
        let fixture = ViewportCoordinatorFixture(
            window: window,
            tests: self,
            visibleRows: NSRange(location: 24, length: 12)
        )
        defer {
            source.releaseAll()
            fixture.detach()
        }

        fixture.coordinator.visibleBoundsChanged()
        let visiblePageTask = try #require(
            fixture.coordinator.pendingPages[2]
        )
        let prefetchedPageTask = try #require(
            fixture.coordinator.pendingPages[3]
        )
        await source.waitUntilStarted(offset: 24, attempt: 1)
        await source.waitUntilStarted(offset: 36, attempt: 1)
        await visiblePageTask.value

        fixture.coordinator.requestVisibleRows(
            visibleRows: IndexSet(integersIn: 24 ..< 36)
        )
        #expect(fixture.coordinator.pendingPages[3] != nil)
        #expect(!prefetchedPageTask.isCancelled)

        fixture.tableView.recordedVisibleRows = NSRange(
            location: 12,
            length: 12
        )
        fixture.coordinator.visibleBoundsChanged()
        #expect(fixture.coordinator.pendingPages[3] == nil)
        #expect(prefetchedPageTask.isCancelled)
    }

    @Test("A prefetch that becomes visible completes without a second load")
    func visiblePrefetchRetainsSingleLoad() async throws {
        let rows = makeTracks(count: 300)
        let source = SuspendedAttemptTrackWindowSource(
            rows: rows,
            suspendedOffset: 132,
            suspendedAttempt: 1
        )
        source.suspend(offset: 120, attempt: 1)
        source.suspend(offset: 144, attempt: 1)
        let window = LibraryTrackWindow(
            pageSize: 12,
            pageCapacity: 3,
            prefetchPages: 1
        ) { _, offset, limit in
            await source.rows(offset: offset, limit: limit)
        }
        await window.configure(
            totalCount: rows.count,
            query: .allTracks,
            contentVersion: TrackTableContentVersion(
                sourceID: deterministicUUID(81000),
                generation: 0
            )
        )

        let fixture = ViewportCoordinatorFixture(
            window: window,
            tests: self,
            visibleRows: NSRange(location: 120, length: 12)
        )
        defer {
            source.releaseAll()
            fixture.detach()
        }

        fixture.coordinator.visibleBoundsChanged()
        let obsoleteTask = try #require(
            fixture.coordinator.pendingPages[10]
        )
        await source.waitUntilStarted(offset: 120, attempt: 1)
        await source.waitUntilStarted(offset: 132, attempt: 1)

        try await completePrefetchTransition(
            fixture: fixture,
            source: source,
            obsoleteTask: obsoleteTask
        )

        #expect(source.observedCancellation(offset: 132, attempt: 1) == false)
        #expect(source.attemptCount(offset: 132) == 1)
        #expect(window.track(at: 132) == rows[132])
    }

    @Test("Reloading an evicted first page keeps ready content mounted")
    func evictedFirstPageReloadKeepsReadyContentMounted() async {
        let rows = makeTracks(count: 24)
        let source = SuspendedAttemptTrackWindowSource(
            rows: rows,
            suspendedOffset: 0,
            suspendedAttempt: 2
        )
        let window = LibraryTrackWindow(
            pageSize: 12,
            pageCapacity: 1,
            prefetchPages: 0
        ) { _, offset, limit in
            await source.rows(offset: offset, limit: limit)
        }
        await window.configure(
            totalCount: rows.count,
            query: .allTracks,
            contentVersion: TrackTableContentVersion(
                sourceID: deterministicUUID(81001),
                generation: 0
            )
        )
        await window.load(
            page: 1,
            allowsPrefetch: false,
            prefetchDirection: .none,
            reportsFirstPageLoading: false
        )
        #expect(window.firstPageState == .ready)
        #expect(window.track(at: 0) == nil)

        let fixture = ViewportCoordinatorFixture(
            window: window,
            tests: self,
            visibleRows: NSRange(location: 0, length: 12)
        )
        defer {
            source.releaseAll()
            fixture.detach()
        }

        fixture.coordinator.visibleBoundsChanged()
        await source.waitUntilStarted(offset: 0, attempt: 2)

        #expect(window.firstPageState == .ready)

        source.release(offset: 0, attempt: 2)
        await drainPendingPageTasks(fixture.coordinator)
    }

    @Test("An identical configuration retries a cancelled first page")
    func sameConfigurationRetriesCancelledFirstPage() async {
        let rows = makeTracks(count: 12)
        let source = SuspendedAttemptTrackWindowSource(
            rows: rows,
            suspendedOffset: 0,
            suspendedAttempt: 1
        )
        let window = LibraryTrackWindow(
            pageSize: 12,
            pageCapacity: 1,
            prefetchPages: 0
        ) { _, offset, limit in
            await source.rows(offset: offset, limit: limit)
        }
        let version = TrackTableContentVersion(
            sourceID: deterministicUUID(81002),
            generation: 0
        )
        let initialConfigure = Task { @MainActor in
            await window.configure(
                totalCount: rows.count,
                query: .allTracks,
                contentVersion: version
            )
        }
        await source.waitUntilStarted(offset: 0, attempt: 1)

        initialConfigure.cancel()
        source.release(offset: 0, attempt: 1)
        await initialConfigure.value

        #expect(source.observedCancellation(offset: 0, attempt: 1) == true)
        #expect(window.firstPageState == .idle)
        #expect(window.track(at: 0) == nil)

        await window.configure(
            totalCount: rows.count,
            query: .allTracks,
            contentVersion: version
        )

        #expect(source.attemptCount(offset: 0) == 2)
        #expect(window.firstPageState == .ready)
        #expect(window.track(at: 0) == rows[0])
    }

    private func completePrefetchTransition(
        fixture: ViewportCoordinatorFixture,
        source: SuspendedAttemptTrackWindowSource,
        obsoleteTask: Task<Void, Never>
    ) async throws {
        fixture.tableView.recordedVisibleRows = NSRange(
            location: 132,
            length: 12
        )
        fixture.coordinator.visibleBoundsChanged()
        let currentPrefetchTask = try #require(
            fixture.coordinator.pendingPages[12]
        )
        await source.waitUntilStarted(offset: 144, attempt: 1)

        source.release(offset: 120, attempt: 1)
        await source.waitUntilFinished(offset: 120, attempt: 1)
        await obsoleteTask.value

        #expect(fixture.coordinator.pendingPages[12] != nil)
        #expect(!currentPrefetchTask.isCancelled)

        source.release(offset: 132, attempt: 1)
        source.release(offset: 144, attempt: 1)
        await source.waitUntilFinished(offset: 132, attempt: 1)
        await currentPrefetchTask.value
        await drainPendingPageTasks(fixture.coordinator)
    }

    private func drainPendingPageTasks(
        _ coordinator: TrackTableCore.Coordinator
    ) async {
        while let task = coordinator.pendingPages.values.first {
            await task.value
        }
    }
}

@MainActor
private final class ViewportCoordinatorFixture {
    let coordinator: TrackTableCore.Coordinator
    let tableView: RecordingTrackTableView
    let scrollView: NSScrollView

    init(
        window: LibraryTrackWindow,
        tests: AllTracksPerformanceTests,
        visibleRows: NSRange
    ) {
        let coordinator = TrackTableCore.Coordinator(
            parent: tests.makeVirtualCore(
                window: window,
                selection: .constant([]),
                probe: nil
            )
        )
        let tableView = RecordingTrackTableView(visibleRows: visibleRows)
        tableView.addTableColumn(NSTableColumn(identifier: .init("row")))
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 12 * 58)
        )
        scrollView.documentView = tableView

        self.coordinator = coordinator
        self.tableView = tableView
        self.scrollView = scrollView
        coordinator.attach(tableView: tableView, scrollView: scrollView)
    }

    func detach() {
        coordinator.detach()
    }
}

@MainActor
private final class SuspendedAttemptTrackWindowSource {
    private struct Request: Hashable {
        let offset: Int
        let attempt: Int
    }

    private let rows: [LibraryTrackProjection]
    private var suspendedRequests: Set<Request>
    private var attemptsByOffset: [Int: Int] = [:]
    private var startedRequests: Set<Request> = []
    private var startWaiters: [
        Request: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var continuations: [
        Request: CheckedContinuation<Void, Never>
    ] = [:]
    private var cancellations: [Request: Bool] = [:]
    private var finishedRequests: Set<Request> = []
    private var finishWaiters: [
        Request: [CheckedContinuation<Void, Never>]
    ] = [:]

    init(
        rows: [LibraryTrackProjection],
        suspendedOffset: Int,
        suspendedAttempt: Int
    ) {
        self.rows = rows
        suspendedRequests = [
            Request(
                offset: suspendedOffset,
                attempt: suspendedAttempt
            ),
        ]
    }

    func rows(
        offset: Int,
        limit: Int
    ) async -> [LibraryTrackProjection] {
        attemptsByOffset[offset, default: 0] += 1
        let request = Request(
            offset: offset,
            attempt: attemptsByOffset[offset, default: 0]
        )
        startedRequests.insert(request)
        startWaiters.removeValue(forKey: request)?
            .forEach { $0.resume() }
        if suspendedRequests.contains(request) {
            await withCheckedContinuation { continuation in
                continuations[request] = continuation
            }
        }
        cancellations[request] = Task.isCancelled
        finishedRequests.insert(request)
        finishWaiters.removeValue(forKey: request)?
            .forEach { $0.resume() }
        guard offset < rows.count else {
            return []
        }
        return Array(rows[offset ..< min(offset + limit, rows.count)])
    }

    func waitUntilStarted(offset: Int, attempt: Int) async {
        let request = Request(offset: offset, attempt: attempt)
        guard !startedRequests.contains(request) else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters[request, default: []].append(continuation)
        }
    }

    func waitUntilFinished(offset: Int, attempt: Int) async {
        let request = Request(offset: offset, attempt: attempt)
        guard !finishedRequests.contains(request) else {
            return
        }
        await withCheckedContinuation { continuation in
            finishWaiters[request, default: []].append(continuation)
        }
    }

    func attemptCount(offset: Int) -> Int {
        attemptsByOffset[offset, default: 0]
    }

    func observedCancellation(offset: Int, attempt: Int) -> Bool? {
        cancellations[Request(offset: offset, attempt: attempt)]
    }

    func suspend(offset: Int, attempt: Int) {
        suspendedRequests.insert(
            Request(offset: offset, attempt: attempt)
        )
    }

    func release(offset: Int, attempt: Int) {
        continuations.removeValue(
            forKey: Request(offset: offset, attempt: attempt)
        )?.resume()
    }

    func releaseAll() {
        let pending = continuations.values
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
