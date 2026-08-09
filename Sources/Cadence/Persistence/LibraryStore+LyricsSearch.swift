import Foundation

extension LibraryStore {
    func synchronizeLyricsSearch() async {
        guard let lyricsSearchIndexer else {
            return
        }
        lyricsSearchIndexState = .indexing
        do {
            try await lyricsSearchIndexer.synchronize()
            lyricsSearchIndexState = .ready
        } catch {
            lyricsSearchIndexState = .failed(error.localizedDescription)
        }
    }

    func synchronizeLyricsSearch(
        trackIDs: Set<UUID>
    ) async {
        guard let lyricsSearchIndexer else {
            return
        }
        do {
            try await lyricsSearchIndexer.synchronize(trackIDs: trackIDs)
            lyricsSearchIndexState = .ready
        } catch {
            lyricsSearchIndexState = .failed(error.localizedDescription)
        }
    }

    func lyricsCatalogResults(
        query: String,
        limit: Int
    ) async -> [LyricsCatalogSearchResult] {
        guard let lyricsSearchIndexer, let repository else {
            return []
        }
        do {
            let matches = try await lyricsSearchIndexer.search(
                query: query,
                limit: limit
            )
            let tracks = try await repository.tracks(
                ids: Set(matches.map(\.trackID))
            )
            let tracksByID = Dictionary(
                uniqueKeysWithValues: tracks.map { ($0.id, $0) }
            )
            return matches.compactMap { match in
                tracksByID[match.trackID].map {
                    LyricsCatalogSearchResult(track: $0, match: match)
                }
            }
        } catch {
            lyricsSearchIndexState = .failed(error.localizedDescription)
            return []
        }
    }
}
