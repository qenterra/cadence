@testable import Cadence
import Foundation
import Testing

@MainActor
struct AllTracksPerformanceTests {
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
            query: .allTracks
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

        await window.configure(totalCount: 1000, query: .allTracks)
        await window.load(page: 8, prefetchDirection: .before)

        #expect(await counter.requests == [0, 64, 512, 448])
    }
}

private actor TrackWindowLoadCounter {
    private(set) var requests: [Int] = []

    func record(offset: Int, limit: Int) {
        guard limit == 64 else {
            return
        }
        requests.append(offset)
    }
}
