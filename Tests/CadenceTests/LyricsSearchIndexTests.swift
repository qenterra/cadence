@testable import Cadence
import Foundation
import Testing

struct LyricsSearchIndexTests {
    @Test("Unicode search returns one best highlighted line per track")
    func unicodeSearch() async throws {
        let fixture = try LyricsSearchIndexFixture()
        try await fixture.index.upsert([
            document(trackID: fixture.trackID, line: 0, text: "Город спит"),
            document(trackID: fixture.trackID, line: 1, text: "Ночь идёт", time: 12),
            document(trackID: fixture.trackID, line: 2, text: "Эта ночь снова", time: 24),
        ])

        let matches = try await fixture.index.search(query: "ночь", limit: 20)

        #expect(matches.count == 1)
        #expect(matches[0].trackID == fixture.trackID)
        #expect(matches[0].snippet.contains("<mark>"))
        #expect([1, 2].contains(matches[0].lineIndex))
    }

    @Test("An unchanged content hash skips redundant indexing")
    func contentHashSkip() async throws {
        let fixture = try LyricsSearchIndexFixture()
        try await fixture.index.upsert([
            document(trackID: fixture.trackID, text: "ocean", hash: "v1"),
        ])
        try await fixture.index.upsert([
            document(trackID: fixture.trackID, text: "wildfire", hash: "v1"),
        ])

        #expect(try await fixture.index.search(query: "wildfire", limit: 10).isEmpty)
        #expect(try await fixture.index.search(query: "ocean", limit: 10).count == 1)

        try await fixture.index.upsert([
            document(trackID: fixture.trackID, text: "wildfire", hash: "v2"),
        ])
        #expect(try await fixture.index.search(query: "wildfire", limit: 10).count == 1)
    }

    @Test("Deleting a track removes all of its lyric lines")
    func deleteTrack() async throws {
        let fixture = try LyricsSearchIndexFixture()
        try await fixture.index.upsert([
            document(trackID: fixture.trackID, text: "temporary words"),
        ])

        try await fixture.index.remove(trackIDs: [fixture.trackID])

        #expect(try await fixture.index.search(query: "temporary", limit: 10).isEmpty)
    }

    @Test("Corrupt derived storage is recreated without touching source lyrics")
    func corruptionRecovery() async throws {
        let fixture = try LyricsSearchIndexFixture(createIndex: false)
        try Data("not a database".utf8).write(to: fixture.databaseURL)

        let index = try LyricsSearchIndex(databaseURL: fixture.databaseURL)
        try await index.upsert([
            document(trackID: fixture.trackID, text: "recovered words"),
        ])

        #expect(try await index.search(query: "recovered", limit: 10).count == 1)
    }

    @Test("Punctuation-only queries are harmless")
    func punctuationQuery() async throws {
        let fixture = try LyricsSearchIndexFixture()
        try await fixture.index.upsert([
            document(trackID: fixture.trackID, text: "ordinary lyrics"),
        ])

        #expect(try await fixture.index.search(query: "\" OR *", limit: 10).isEmpty)
    }

    private func document(
        trackID: UUID,
        line: Int = 0,
        text: String,
        time: TimeInterval? = nil,
        hash: String = "content-v1"
    ) -> LyricsSearchDocument {
        LyricsSearchDocument(
            trackID: trackID,
            lineIndex: line,
            timestamp: time,
            text: text,
            contentHash: hash
        )
    }
}

private struct LyricsSearchIndexFixture {
    let root: URL
    let databaseURL: URL
    let trackID = UUID()
    let index: LyricsSearchIndex

    init(createIndex: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Lyrics-Search-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        databaseURL = root.appending(path: "Search.sqlite")
        index = createIndex
            ? try LyricsSearchIndex(databaseURL: databaseURL)
            : try LyricsSearchIndex(
                databaseURL: root.appending(path: "Placeholder.sqlite")
            )
    }
}
