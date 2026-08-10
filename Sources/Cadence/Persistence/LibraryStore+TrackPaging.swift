import Foundation

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

        let generation = trackRequestGeneration
        let query = trackQuery
        isLoadingNextTracks = true
        availability = .loading
        do {
            let page = try await trackPageLoader(query, trackCursor)
            guard
                generation == trackRequestGeneration,
                query == trackQuery
            else {
                return
            }
            appendUniqueTracks(page.items)
            self.trackCursor = page.nextCursor
            isLoadingNextTracks = false
            availability = .ready
        } catch {
            guard generation == trackRequestGeneration else {
                return
            }
            isLoadingNextTracks = false
            availability = .ready
            recordOperationFailure(.trackPage, error: error)
        }
    }

    func replaceTracks(search: String) async {
        searchQuery = search
        await replaceTracks(
            query: LibraryTrackQuery(
                scope: trackQuery.scope,
                search: search,
                sort: trackQuery.sort
            )
        )
    }

    func replaceTracks(query: LibraryTrackQuery) async {
        trackRequestGeneration += 1
        let generation = trackRequestGeneration
        trackQuery = query
        searchQuery = query.search
        isLoadingNextTracks = false

        guard let trackPageLoader else {
            tracks = []
            trackCursor = nil
            availability = .empty
            return
        }

        availability = .loading
        do {
            let page = try await trackPageLoader(query, nil)
            guard
                generation == trackRequestGeneration,
                query == trackQuery
            else {
                return
            }
            tracks = deduplicatedTracks(page.items)
            trackCursor = page.nextCursor
            availability = .ready
        } catch {
            guard generation == trackRequestGeneration else {
                return
            }
            availability = .ready
            recordOperationFailure(.trackPage, error: error)
        }
    }

    func showImportedTracks(
        importID: UUID
    ) async {
        guard let repository else {
            return
        }
        availability = .loading
        trackRequestGeneration += 1
        isLoadingNextTracks = false
        do {
            tracks = try await repository.importedTracks(
                importID: importID
            )
            trackCursor = nil
            trackQuery = .allTracks
            searchQuery = ""
            availability = .ready
        } catch {
            availability = .ready
            recordOperationFailure(.trackPage, error: error)
        }
    }

    @discardableResult
    func recordRecentlyPlayed(
        trackID: UUID,
        at date: Date = .now
    ) async -> Bool {
        guard let repository else {
            return false
        }
        do {
            try await repository.recordRecentlyPlayed(
                trackID: trackID,
                at: date
            )
            recentlyPlayedTracks = try await repository.recentlyPlayedTracks()
            let recentByID = Dictionary(
                uniqueKeysWithValues: recentlyPlayedTracks.map { ($0.id, $0) }
            )
            tracks = tracks.map { recentByID[$0.id] ?? $0 }
            return true
        } catch {
            return false
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
        tracks.append(
            contentsOf: projections.filter {
                existingIDs.insert($0.id).inserted
            }
        )
    }
}
