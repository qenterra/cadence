import Foundation

struct LibraryRecentPlaybackResult: Sendable {
    let projection: LibraryTrackProjection?
    let recentlyPlayedTracks: [LibraryTrackProjection]
}

typealias LibraryRecentPlaybackOperation = @Sendable (
    _ repository: LibraryRepository,
    _ trackID: UUID,
    _ date: Date
) async throws -> LibraryRecentPlaybackResult

typealias LibraryRecentlyPlayedTracksLoader = @Sendable (
    _ repository: LibraryRepository
) async throws -> [LibraryTrackProjection]

extension LibraryStore {
    func loadInitialTracks() async {
        await replaceTracks(query: trackQuery)
    }

    func searchTracks(_ query: String) async {
        searchQuery = query
        await replaceTracks(
            query: LibraryTrackQuery(
                scope: trackQuery.scope,
                search: query,
                sort: trackQuery.sort
            )
        )
    }

    func sortTracks(_ sort: LibraryTrackSort) async {
        guard sort != trackQuery.sort else {
            return
        }
        await replaceTracks(
            query: LibraryTrackQuery(
                scope: trackQuery.scope,
                search: trackQuery.search,
                sort: sort
            )
        )
    }

    func loadNextTracks() async {
        guard
            let trackPageLoader,
            let trackCursor,
            !isLoadingNextTracks
        else {
            return
        }

        let context = captureLibraryContext()
        let generation = trackRequestGeneration
        let query = trackQuery
        isLoadingNextTracks = true
        availability = .loading
        do {
            let page = try await trackPageLoader(query, trackCursor)
            guard
                generation == trackRequestGeneration,
                query == trackQuery,
                isCurrentLibraryContext(context)
            else {
                return
            }
            appendUniqueTracks(page.items)
            self.trackCursor = page.nextCursor
            isLoadingNextTracks = false
            availability = .ready
        } catch {
            guard
                generation == trackRequestGeneration,
                isCurrentLibraryContext(context)
            else {
                return
            }
            isLoadingNextTracks = false
            availability = .ready
            recordOperationFailure(.trackPage, error: error)
        }
    }

    func replaceTracks(query: LibraryTrackQuery) async {
        let context = captureLibraryContext()
        trackRequestGeneration += 1
        let generation = trackRequestGeneration
        trackQuery = query
        searchQuery = query.search
        isLoadingNextTracks = false

        guard let trackPageLoader else {
            replaceTracksContent(with: [])
            trackCursor = nil
            availability = .empty
            return
        }

        availability = .loading
        do {
            let page = try await trackPageLoader(query, nil)
            guard
                generation == trackRequestGeneration,
                query == trackQuery,
                isCurrentLibraryContext(context)
            else {
                return
            }
            replaceTracksContent(
                with: deduplicatedTracks(page.items)
            )
            trackCursor = page.nextCursor
            availability = .ready
        } catch {
            guard
                generation == trackRequestGeneration,
                isCurrentLibraryContext(context)
            else {
                return
            }
            availability = .ready
            recordOperationFailure(.trackPage, error: error)
        }
    }

    func showImportedTracks(
        importID: UUID
    ) async {
        let context = captureLibraryContext()
        availability = .loading
        trackRequestGeneration += 1
        let generation = trackRequestGeneration
        isLoadingNextTracks = false
        do {
            let repository = try requireRepository()
            let importedTracks = try await repository.importedTracks(
                importID: importID
            )
            guard
                generation == trackRequestGeneration,
                isCurrentLibraryContext(context)
            else {
                return
            }
            replaceTracksContent(with: importedTracks)
            trackCursor = nil
            trackQuery = .allTracks
            searchQuery = ""
            availability = .ready
        } catch {
            guard
                generation == trackRequestGeneration,
                isCurrentLibraryContext(context)
            else {
                return
            }
            availability = .ready
            recordOperationFailure(.trackPage, error: error)
        }
    }

    @discardableResult
    func recordRecentlyPlayed(
        trackID: UUID,
        at date: Date = .now,
        operation: LibraryRecentPlaybackOperation? = nil,
        recentTracksLoader: LibraryRecentlyPlayedTracksLoader? = nil
    ) async -> Bool {
        let context = captureLibraryContext()
        let repository: LibraryRepository
        do {
            repository = try requireRepository()
        } catch {
            guard isCurrentLibraryContext(context) else {
                return false
            }
            recordOperationFailure(.recentPlayback, error: error)
            return false
        }

        if let operation {
            do {
                let result = try await operation(
                    repository,
                    trackID,
                    date
                )
                guard isCurrentLibraryContext(context) else {
                    return true
                }
                if let projection = result.projection {
                    publishTrackProjection(projection)
                }
                recentlyPlayedTracks = result.recentlyPlayedTracks
                return true
            } catch {
                guard isCurrentLibraryContext(context) else {
                    return false
                }
                recordOperationFailure(.recentPlayback, error: error)
                return false
            }
        }

        let projection: LibraryTrackProjection?
        do {
            projection = try await repository.recordRecentlyPlayed(
                trackID: trackID,
                at: date
            )
        } catch {
            guard isCurrentLibraryContext(context) else {
                return false
            }
            recordOperationFailure(.recentPlayback, error: error)
            return false
        }

        guard isCurrentLibraryContext(context) else {
            return true
        }
        do {
            let recentTracks = if let recentTracksLoader {
                try await recentTracksLoader(repository)
            } else {
                try await repository.recentlyPlayedTracks()
            }
            guard isCurrentLibraryContext(context) else {
                return true
            }
            if let projection {
                publishTrackProjection(projection)
            }
            recentlyPlayedTracks = recentTracks
            return true
        } catch {
            guard isCurrentLibraryContext(context) else {
                return true
            }
            if let projection {
                publishTrackProjection(projection)
            }
            recordOperationFailure(.recentPlayback, error: error)
            return true
        }
    }
}

extension LibraryStore {
    func deduplicatedTracks(
        _ projections: [LibraryTrackProjection]
    ) -> [LibraryTrackProjection] {
        var seen: Set<UUID> = []
        return projections.filter { seen.insert($0.id).inserted }
    }

    private func appendUniqueTracks(
        _ projections: [LibraryTrackProjection]
    ) {
        var existingIDs = Set(tracks.map(\.id))
        let additions = projections.filter {
            existingIDs.insert($0.id).inserted
        }
        guard !additions.isEmpty else {
            return
        }
        tracks.append(contentsOf: additions)
        tracksContentClock.advance()
    }
}
