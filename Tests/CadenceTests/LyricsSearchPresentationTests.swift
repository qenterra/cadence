@testable import Cadence
import Foundation
import Testing

@MainActor
struct LyricsSearchPresentationTests {
    @Test("Opening a lyric match reveals it without starting playback")
    func revealWithoutPlayback() {
        let model = CadenceAppModel.testFixture()
        let result = searchResult()
        model.previewIsPlaying = false

        model.presentLyricsSearchResult(result)

        #expect(model.playbackWorkspace == .lyricsSearch)
        #expect(model.lyricsSearchTarget == result)
        #expect(!model.previewIsPlaying)
    }

    @Test("Closing lyric search returns to catalog results")
    func closePreview() {
        let model = CadenceAppModel.testFixture()
        model.presentLyricsSearchResult(searchResult())

        model.dismissLyricsSearchResult()

        #expect(model.playbackWorkspace == .hidden)
        #expect(model.lyricsSearchTarget == nil)
    }

    private func searchResult() -> LyricsCatalogSearchResult {
        let trackID = UUID()
        return LyricsCatalogSearchResult(
            track: LibraryTrackProjection(
                id: trackID,
                title: "Signal",
                artistID: nil,
                artist: "North Assembly",
                albumID: nil,
                album: "After Dark",
                duration: 180,
                year: 2026,
                codec: "FLAC",
                sampleRate: 48000,
                channelCount: 2,
                bitDepth: 24,
                isFavorite: false,
                customArtworkID: nil,
                artworkID: nil,
                relativeMediaPath: "Media/\(trackID.uuidString).flac",
                dateAdded: .now,
                lastPlayedAt: nil,
                playCount: 0,
                hasSynchronizedLyrics: true
            ),
            match: LyricsSearchMatch(
                trackID: trackID,
                lineIndex: 3,
                timestamp: 24,
                snippet: "A <mark>signal</mark> remains",
                score: -1
            )
        )
    }
}
