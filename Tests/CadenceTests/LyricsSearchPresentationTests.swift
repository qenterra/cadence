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

    @Test("Artwork publication refreshes the open lyric match in place")
    func artworkPublicationRefreshesOpenMatch() {
        let model = CadenceAppModel.testFixture()
        let result = searchResult()
        let artworkID = UUID()
        let updatedTrack = replacingArtwork(
            in: result.track,
            with: artworkID
        )
        let effect = ManagedArtworkPublicationEffect(
            ownerKind: .track,
            ownerID: result.track.id,
            previousArtworkID: nil,
            newArtworkID: artworkID
        )
        model.presentLyricsSearchResult(result)
        let store = model.librarySession.store
        store.artworkPublication = LibraryArtworkPublication(
            epoch: store.libraryEpoch,
            generation: 1,
            effects: [effect],
            payload: LibraryArtworkPublicationPayload(
                tracksByID: [updatedTrack.id: updatedTrack],
                albumsByID: [:],
                artistsByID: [:],
                playlistsByID: [:]
            )
        )

        model.applyManagedArtworkPublication([effect])

        #expect(model.lyricsSearchTarget?.track.artworkID == artworkID)
        #expect(model.lyricsSearchTarget?.match == result.match)
        #expect(model.playbackWorkspace == .lyricsSearch)
        #expect(model.artworkRevision == 1)
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
                isExplicit: false,
                customArtworkID: nil,
                artworkID: nil,
                relativeMediaPath: "Media/\(trackID.uuidString).flac",
                lastPlayedAt: nil,
                hasSynchronizedLyrics: true
            ),
            match: LyricsSearchMatch(
                trackID: trackID,
                lineIndex: 3,
                timestamp: 24,
                snippet: "A <mark>signal</mark> remains"
            )
        )
    }

    private func replacingArtwork(
        in track: LibraryTrackProjection,
        with artworkID: UUID
    ) -> LibraryTrackProjection {
        LibraryTrackProjection(
            id: track.id,
            title: track.title,
            artistID: track.artistID,
            artist: track.artist,
            albumID: track.albumID,
            album: track.album,
            duration: track.duration,
            year: track.year,
            codec: track.codec,
            sampleRate: track.sampleRate,
            channelCount: track.channelCount,
            bitDepth: track.bitDepth,
            isFavorite: track.isFavorite,
            isExplicit: track.isExplicit,
            customArtworkID: artworkID,
            artworkID: artworkID,
            relativeMediaPath: track.relativeMediaPath,
            lastPlayedAt: track.lastPlayedAt,
            hasSynchronizedLyrics: track.hasSynchronizedLyrics
        )
    }
}
