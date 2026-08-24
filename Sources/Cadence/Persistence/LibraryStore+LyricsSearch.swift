import Foundation

extension LibraryStore {
    func synchronizeLyricsSearch() async {
        await synchronizeLyricsSearch(for: captureLibraryContext())
    }

    func synchronizeLyricsSearch(
        trackIDs: Set<UUID>,
        for context: LibraryStoreContext,
        indexer: any LyricsSearchIndexing
    ) async {
        guard
            let task = startAttachmentTask(context: context, operation: { [weak self, indexer] in
                await self?.performLyricsSearchSynchronization(
                    trackIDs: trackIDs,
                    context: context,
                    indexer: indexer
                )
            })
        else {
            return
        }
        _ = try? await task.value
    }

    func synchronizeLyricsSearch(
        for context: LibraryStoreContext
    ) async {
        guard
            let indexer = lyricsSearchIndexer,
            let task = startAttachmentTask(context: context, operation: { [weak self, indexer] in
                await self?.performLyricsSearchSynchronization(
                    context: context,
                    indexer: indexer
                )
            })
        else {
            return
        }
        _ = try? await task.value
    }

    func lyricsCatalogResults(
        query: String,
        limit: Int
    ) async -> [LyricsCatalogSearchResult] {
        let context = captureLibraryContext()
        guard
            let indexer = lyricsSearchIndexer,
            let repository = try? requireRepository(),
            let task = startAttachmentTask(context: context, operation: { [weak self, indexer, repository] in
                guard let self,
                      ownsLyricsSearch(context, indexer: indexer) else {
                    throw CancellationError()
                }
                let matches = try await indexer.search(
                    query: query,
                    limit: limit
                )
                guard ownsLyricsSearch(context, indexer: indexer) else {
                    throw CancellationError()
                }
                let tracks = try await repository.tracks(
                    ids: Set(matches.map(\.trackID))
                )
                guard ownsLyricsSearch(context, indexer: indexer) else {
                    throw CancellationError()
                }
                let tracksByID = Dictionary(
                    uniqueKeysWithValues: tracks.map { ($0.id, $0) }
                )
                return matches.compactMap { match in
                    tracksByID[match.trackID].map {
                        LyricsCatalogSearchResult(track: $0, match: match)
                    }
                }
            })
        else {
            return []
        }
        do {
            return try await task.value
        } catch {
            guard ownsLyricsSearch(context, indexer: indexer) else {
                return []
            }
            lyricsSearchIndexState = .failed(error.localizedDescription)
            recordOperationFailure(.catalogSearch, error: error)
            return []
        }
    }
}

private extension LibraryStore {
    func performLyricsSearchSynchronization(
        context: LibraryStoreContext,
        indexer: any LyricsSearchIndexing
    ) async {
        guard ownsLyricsSearch(context, indexer: indexer) else {
            return
        }
        lyricsSearchIndexState = .indexing
        do {
            try await indexer.synchronize()
            guard ownsLyricsSearch(context, indexer: indexer) else {
                return
            }
            lyricsSearchIndexState = .ready
        } catch {
            guard ownsLyricsSearch(context, indexer: indexer) else {
                return
            }
            lyricsSearchIndexState = .failed(error.localizedDescription)
        }
    }

    func performLyricsSearchSynchronization(
        trackIDs: Set<UUID>,
        context: LibraryStoreContext,
        indexer: any LyricsSearchIndexing
    ) async {
        guard ownsLyricsSearch(context, indexer: indexer) else {
            return
        }
        do {
            try await indexer.synchronize(trackIDs: trackIDs)
            guard ownsLyricsSearch(context, indexer: indexer) else {
                return
            }
            lyricsSearchIndexState = .ready
        } catch {
            guard ownsLyricsSearch(context, indexer: indexer) else {
                return
            }
            lyricsSearchIndexState = .failed(error.localizedDescription)
        }
    }

    func ownsLyricsSearch(
        _ context: LibraryStoreContext,
        indexer: any LyricsSearchIndexing
    ) -> Bool {
        isCurrentLibraryContext(context)
            && lyricsSearchIndexer === indexer
    }
}
