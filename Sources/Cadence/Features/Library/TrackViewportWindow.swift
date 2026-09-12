import Foundation
import Observation
import QenTerraFoundation

typealias LibraryTrackWindowLoader = @Sendable (
    _ query: LibraryTrackQuery,
    _ offset: Int,
    _ limit: Int
) async throws -> [LibraryTrackProjection]

enum TrackViewportLoadState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
}

@MainActor
@Observable
final class LibraryTrackWindow {
    let pageSize: Int
    private let prefetchPages: Int
    private let loader: LibraryTrackWindowLoader

    private(set) var totalCount = 0
    private(set) var query = LibraryTrackQuery.allTracks
    private(set) var contentVersion: TrackTableContentVersion?
    private(set) var revision = 0
    private(set) var firstPageState = TrackViewportLoadState.idle

    @ObservationIgnored
    private var pages: PageWindow<LibraryTrackProjection>
    @ObservationIgnored
    private var requests: PageRequestTracker
    @ObservationIgnored
    private var generation = 0

    init(
        pageSize: Int = 64,
        pageCapacity: Int = 5,
        prefetchPages: Int = 1,
        loader: @escaping LibraryTrackWindowLoader
    ) {
        let boundedPageSize = min(max(pageSize, 1), 200)
        self.pageSize = boundedPageSize
        self.prefetchPages = max(prefetchPages, 0)
        self.loader = loader
        pages = PageWindow(pageCapacity: pageCapacity)
        requests = PageRequestTracker(pageSize: boundedPageSize)
    }

    var pageCount: Int {
        guard totalCount > 0 else {
            return 0
        }
        return (totalCount + pageSize - 1) / pageSize
    }

    func needsLoad(page: Int) -> Bool {
        guard page >= 0, page < pageCount else {
            return false
        }
        return requests.needsRequest(containing: page * pageSize)
    }

    func desiredPages(for visibleRows: IndexSet) -> [Int] {
        guard
            pageCount > 0,
            let firstRow = visibleRows.first,
            let lastRow = visibleRows.last
        else {
            return []
        }
        let firstPage = max(firstRow / pageSize, 0)
        let lastPage = min(lastRow / pageSize, pageCount - 1)
        guard firstPage <= lastPage else {
            return []
        }
        return Array(firstPage ... lastPage)
    }

    func prefetchCandidates(
        around page: Int,
        direction: PagePrefetchDirection
    ) -> [Int] {
        PagePrefetchPolicy.pages(
            around: page,
            pageCount: pageCount,
            prefetchPages: prefetchPages,
            direction: direction
        )
    }

    func configure(
        totalCount: Int,
        query: LibraryTrackQuery,
        contentVersion: TrackTableContentVersion
    ) async {
        let boundedCount = max(totalCount, 0)
        let replacesSource = self.contentVersion?.sourceID
            != contentVersion.sourceID
        guard
            boundedCount != self.totalCount
            || query != self.query
            || replacesSource
        else {
            guard self.contentVersion != contentVersion else {
                if boundedCount == 0 {
                    firstPageState = .ready
                } else if firstPageState == .idle {
                    await retryFirstPage()
                }
                return
            }
            generation &+= 1
            let configurationGeneration = generation
            requests.invalidate()
            let cachedPageIndexes = pages.cachedPageIndexes
            if cachedPageIndexes.isEmpty, boundedCount > 0 {
                await load(page: 0)
                guard generation == configurationGeneration else {
                    return
                }
                self.contentVersion = contentVersion
                return
            }
            for page in cachedPageIndexes {
                await load(
                    page: page,
                    allowsPrefetch: false,
                    prefetchDirection: .none,
                    reportsFirstPageLoading: false
                )
                guard generation == configurationGeneration else {
                    return
                }
            }
            self.contentVersion = contentVersion
            if boundedCount == 0 {
                firstPageState = .ready
            }
            return
        }
        self.contentVersion = contentVersion
        self.totalCount = boundedCount
        self.query = query
        generation &+= 1
        pages.removeAll()
        requests.invalidate()
        revision &+= 1
        if boundedCount > 0 {
            firstPageState = .loading
            await load(page: 0)
        } else {
            firstPageState = .ready
        }
    }

    func retryFirstPage() async {
        guard totalCount > 0 else {
            firstPageState = .ready
            return
        }
        firstPageState = .loading
        await load(page: 0)
    }

    func track(at index: Int) -> LibraryTrackProjection? {
        _ = revision
        return pages.item(at: index, pageSize: pageSize)
    }

    func index(ofTrackID trackID: UUID) -> Int? {
        pages.index(
            where: { $0.id == trackID },
            pageSize: pageSize
        )
    }

    func replace(_ track: LibraryTrackProjection) {
        guard pages.replace(where: { $0.id == track.id }, with: track) else {
            return
        }
        revision &+= 1
    }

    func load(
        page: Int,
        allowsPrefetch: Bool = true,
        prefetchDirection: PagePrefetchDirection = .after,
        reportsFirstPageLoading: Bool = true
    ) async {
        guard
            !Task.isCancelled,
            page >= 0,
            page < pageCount,
            let requestedPage = requests.beginRequest(
                containing: page * pageSize
            )
        else {
            return
        }
        let requestQuery = query
        let requestGeneration = generation
        if requestedPage == 0, reportsFirstPageLoading {
            firstPageState = .loading
        }
        do {
            try Task.checkCancellation()
            let items = try await loader(
                requestQuery,
                requestedPage * pageSize,
                pageSize
            )
            try Task.checkCancellation()
            guard
                requestGeneration == generation,
                requestQuery == query
            else {
                return
            }
            await acceptLoadedPage(
                items,
                page: requestedPage,
                allowsPrefetch: allowsPrefetch,
                prefetchDirection: prefetchDirection
            )
        } catch is CancellationError where Task.isCancelled {
            guard
                requestGeneration == generation,
                requestQuery == query
            else {
                return
            }
            requests.failRequest(page: requestedPage)
            if requestedPage == 0, reportsFirstPageLoading {
                firstPageState = .idle
            }
        } catch {
            guard
                requestGeneration == generation,
                requestQuery == query
            else {
                return
            }
            requests.failRequest(page: requestedPage)
            if requestedPage == 0, reportsFirstPageLoading {
                firstPageState = .failed(error.localizedDescription)
            }
        }
    }

    private func acceptLoadedPage(
        _ items: [LibraryTrackProjection],
        page: Int,
        allowsPrefetch: Bool,
        prefetchDirection: PagePrefetchDirection
    ) async {
        let evictedPage = pages.insert(items, page: page)
        requests.finishRequest(page: page)
        if page == 0 {
            firstPageState = .ready
        }
        if let evictedPage {
            requests.forgetRequest(page: evictedPage)
        }
        revision &+= 1
        if allowsPrefetch {
            await prefetch(around: page, direction: prefetchDirection)
        }
    }

    private func prefetch(
        around page: Int,
        direction: PagePrefetchDirection
    ) async {
        for candidate in PagePrefetchPolicy.pages(
            around: page,
            pageCount: pageCount,
            prefetchPages: prefetchPages,
            direction: direction
        ) {
            await load(
                page: candidate,
                allowsPrefetch: false,
                prefetchDirection: .none
            )
        }
    }
}
