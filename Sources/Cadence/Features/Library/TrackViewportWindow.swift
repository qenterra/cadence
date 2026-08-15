import Foundation
import Observation

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

enum TrackViewportPrefetchDirection {
    case before
    case after
    case none
}

struct TrackPageWindow<Element> {
    private let pageCapacity: Int
    private var pages: [Int: [Element]] = [:]
    private var recency: [Int] = []

    init(pageCapacity: Int) {
        self.pageCapacity = max(pageCapacity, 1)
    }

    var cachedPageCount: Int {
        pages.count
    }

    mutating func item(
        at index: Int,
        pageSize: Int
    ) -> Element? {
        guard index >= 0, pageSize > 0 else {
            return nil
        }
        let page = index / pageSize
        let offset = index % pageSize
        guard let items = pages[page], items.indices.contains(offset) else {
            return nil
        }
        touch(page)
        return items[offset]
    }

    @discardableResult
    mutating func insert(
        _ items: [Element],
        page: Int
    ) -> Int? {
        guard page >= 0 else {
            return nil
        }
        pages[page] = items
        touch(page)
        var evictedPage: Int?
        while pages.count > pageCapacity, let leastRecent = recency.first {
            pages[leastRecent] = nil
            recency.removeFirst()
            evictedPage = leastRecent
        }
        return evictedPage
    }

    mutating func removeAll() {
        pages.removeAll(keepingCapacity: true)
        recency.removeAll(keepingCapacity: true)
    }

    mutating func index(
        where predicate: (Element) -> Bool,
        pageSize: Int
    ) -> Int? {
        guard pageSize > 0 else {
            return nil
        }
        for page in Array(recency.reversed()) {
            guard
                let offset = pages[page]?.firstIndex(where: predicate)
            else {
                continue
            }
            touch(page)
            return page * pageSize + offset
        }
        return nil
    }

    mutating func replace(
        where predicate: (Element) -> Bool,
        with replacement: Element
    ) -> Bool {
        for page in pages.keys {
            guard let offset = pages[page]?.firstIndex(where: predicate) else {
                continue
            }
            pages[page]?[offset] = replacement
            touch(page)
            return true
        }
        return false
    }

    private mutating func touch(_ page: Int) {
        recency.removeAll { $0 == page }
        recency.append(page)
    }
}

struct TrackViewportPageRequests {
    private let pageSize: Int
    private var loadingPages: Set<Int> = []
    private var completedPages: Set<Int> = []

    init(pageSize: Int) {
        self.pageSize = max(pageSize, 1)
    }

    mutating func beginRequest(
        containing row: Int
    ) -> Int? {
        guard row >= 0 else {
            return nil
        }
        let page = row / pageSize
        guard
            !loadingPages.contains(page),
            !completedPages.contains(page)
        else {
            return nil
        }
        loadingPages.insert(page)
        return page
    }

    mutating func finishRequest(page: Int) {
        loadingPages.remove(page)
        completedPages.insert(page)
    }

    mutating func forgetRequest(page: Int) {
        loadingPages.remove(page)
        completedPages.remove(page)
    }

    mutating func failRequest(page: Int) {
        loadingPages.remove(page)
    }

    mutating func invalidate() {
        loadingPages.removeAll(keepingCapacity: true)
        completedPages.removeAll(keepingCapacity: true)
    }
}

@MainActor
@Observable
final class LibraryTrackWindow {
    let pageSize: Int
    private let prefetchPages: Int
    private let loader: LibraryTrackWindowLoader

    private(set) var totalCount = 0
    private(set) var query = LibraryTrackQuery.allTracks
    private(set) var revision = 0
    private(set) var firstPageState = TrackViewportLoadState.idle

    @ObservationIgnored
    private var pages: TrackPageWindow<LibraryTrackProjection>
    @ObservationIgnored
    private var requests: TrackViewportPageRequests
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
        pages = TrackPageWindow(pageCapacity: pageCapacity)
        requests = TrackViewportPageRequests(pageSize: boundedPageSize)
    }

    var pageCount: Int {
        guard totalCount > 0 else {
            return 0
        }
        return (totalCount + pageSize - 1) / pageSize
    }

    func configure(
        totalCount: Int,
        query: LibraryTrackQuery
    ) async {
        let boundedCount = max(totalCount, 0)
        guard boundedCount != self.totalCount || query != self.query else {
            if boundedCount > 0 {
                await load(page: 0)
            } else {
                firstPageState = .ready
            }
            return
        }
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
        prefetchDirection: TrackViewportPrefetchDirection = .after
    ) async {
        guard
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
        if requestedPage == 0 {
            firstPageState = .loading
        }
        do {
            let items = try await loader(
                requestQuery,
                requestedPage * pageSize,
                pageSize
            )
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
        } catch {
            guard
                requestGeneration == generation,
                requestQuery == query
            else {
                return
            }
            requests.failRequest(page: requestedPage)
            if requestedPage == 0 {
                firstPageState = .failed(error.localizedDescription)
            }
        }
    }

    private func acceptLoadedPage(
        _ items: [LibraryTrackProjection],
        page: Int,
        allowsPrefetch: Bool,
        prefetchDirection: TrackViewportPrefetchDirection
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
        direction: TrackViewportPrefetchDirection
    ) async {
        for candidate in TrackViewportPrefetch.pages(
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

enum TrackViewportPrefetch {
    static func pages(
        around page: Int,
        pageCount: Int,
        prefetchPages: Int,
        direction: TrackViewportPrefetchDirection
    ) -> [Int] {
        guard
            pageCount > 0,
            prefetchPages > 0,
            page >= 0,
            page < pageCount
        else {
            return []
        }
        switch direction {
        case .before:
            let lowerBound = max(page - prefetchPages, 0)
            guard lowerBound < page else {
                return []
            }
            return Array((lowerBound ..< page).reversed())
        case .after:
            let upperBound = min(page + prefetchPages, pageCount - 1)
            guard page < upperBound else {
                return []
            }
            return Array((page + 1) ... upperBound)
        case .none:
            return []
        }
    }

    static func range(
        visibleRows: ClosedRange<Int>,
        totalCount: Int,
        pageSize: Int,
        prefetchPages: Int
    ) -> ClosedRange<Int>? {
        guard totalCount > 0, pageSize > 0 else {
            return nil
        }
        let lowerPage = max(visibleRows.lowerBound, 0) / pageSize
        let upperPage = max(visibleRows.upperBound, 0) / pageSize
            + max(prefetchPages, 0)
        let lowerBound = min(lowerPage * pageSize, totalCount - 1)
        let upperBound = min(
            (upperPage + 1) * pageSize - 1,
            totalCount - 1
        )
        return lowerBound ... upperBound
    }
}
