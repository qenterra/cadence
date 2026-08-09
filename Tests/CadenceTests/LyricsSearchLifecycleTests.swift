@testable import Cadence
import Foundation
import Testing

struct LyricsSearchLifecycleTests {
    @Test("Save, edit, remove, and restore keep the derived index consistent")
    func lifecycle() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let indexer = try LyricsSearchIndexer(
            package: fixture.package,
            repository: fixture.repository
        )

        try await fixture.service.save(
            document(trackID: fixture.trackID, text: "first constellation")
        )
        try await indexer.synchronize()
        #expect(try await indexer.search(query: "first", limit: 10).count == 1)

        try await fixture.service.save(
            document(trackID: fixture.trackID, text: "second horizon")
        )
        try await indexer.synchronize(trackIDs: [fixture.trackID])
        #expect(try await indexer.search(query: "first", limit: 10).isEmpty)
        #expect(try await indexer.search(query: "second", limit: 10).count == 1)

        try await fixture.service.save(
            LyricDocument(
                trackID: fixture.trackID,
                lines: [LyricLine(text: "")]
            )
        )
        try await indexer.synchronize(trackIDs: [fixture.trackID])
        #expect(try await indexer.search(query: "second", limit: 10).isEmpty)

        try await fixture.service.save(
            document(trackID: fixture.trackID, text: "second horizon")
        )
        try await indexer.synchronize(trackIDs: [fixture.trackID])
        #expect(try await indexer.search(query: "second", limit: 10).count == 1)
    }

    @Test("Catalog search merges lyric matches with track projections")
    @MainActor
    func catalogSearchIntegration() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        try await fixture.service.save(
            document(trackID: fixture.trackID, text: "constellation signal")
        )
        let store = LibraryStore()
        store.attach(
            repository: fixture.repository,
            package: fixture.package
        )

        await store.loadInitialLibrary()
        await store.searchCatalog("constellation")

        #expect(store.catalogSearchResults.lyrics.count == 1)
        #expect(store.catalogSearchResults.lyrics[0].track.id == fixture.trackID)
        #expect(store.catalogSearchResults.tracks.isEmpty)
    }

    @Test("A damaged lyric source removes its stale search result")
    func damagedSource() async throws {
        let fixture = try ManagedLyricsFixture()
        defer { fixture.remove() }
        let indexer = try LyricsSearchIndexer(
            package: fixture.package,
            repository: fixture.repository
        )
        try await fixture.service.save(
            document(trackID: fixture.trackID, text: "fragile signal")
        )
        try await indexer.synchronize()
        try Data("changed outside Cadence\n".utf8).write(
            to: fixture.package.lyricURL(trackID: fixture.trackID)
        )

        await #expect(throws: ManagedLyricsServiceError.self) {
            try await indexer.synchronize(trackIDs: [fixture.trackID])
        }

        #expect(try await indexer.search(query: "fragile", limit: 10).isEmpty)
    }

    private func document(
        trackID: UUID,
        text: String
    ) -> LyricDocument {
        LyricDocument(
            trackID: trackID,
            lines: [LyricLine(text: text, startTime: 4)]
        )
    }
}
