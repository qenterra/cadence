@testable import Cadence
import Testing

@MainActor
struct NowPlayingLifecycleTests {
    @Test("Now Playing chooses Lyrics or Queue from the current track")
    func firstOpenPanel() throws {
        let model = CadenceAppModel()

        #expect(model.presentNowPlaying())
        #expect(model.playbackWorkspace == .nowPlaying)
        #expect(model.selectedNowPlayingPanel == .lyrics)

        model.dismissNowPlaying()
        let trackWithoutLyrics = try #require(
            model.tracks.first { model.lyricDocuments[$0.id] == nil }
        )
        model.currentTrackID = trackWithoutLyrics.id

        #expect(model.presentNowPlaying())
        #expect(model.selectedNowPlayingPanel == .queue)
    }

    @Test("Ordinary opening remembers explicit panel selection")
    func panelMemory() {
        let model = CadenceAppModel()
        model.presentNowPlaying()

        model.selectNowPlayingPanel(.queue)
        model.dismissNowPlaying()
        model.presentNowPlaying()

        #expect(model.selectedNowPlayingPanel == .queue)
    }

    @Test("Queue entry overrides but does not replace remembered panel")
    func queueOverride() {
        let model = CadenceAppModel()
        model.presentNowPlaying()
        model.selectNowPlayingPanel(.lyrics)
        model.dismissNowPlaying()

        #expect(model.presentPlaybackQueue())
        #expect(model.selectedNowPlayingPanel == .queue)

        model.dismissNowPlaying()
        model.presentNowPlaying()
        #expect(model.selectedNowPlayingPanel == .lyrics)
    }

    @Test("Now Playing requires a current track")
    func requiresCurrentTrack() {
        let model = CadenceAppModel()
        model.currentTrackID = nil

        #expect(!model.presentNowPlaying())
        #expect(model.playbackWorkspace == .hidden)
    }

    @Test("Rail navigation closes the playback workspace")
    func destinationNavigation() {
        let model = CadenceAppModel()
        model.presentNowPlaying()

        model.requestNavigationDestination(.tags)

        #expect(model.playbackWorkspace == .hidden)
        #expect(model.selectedDestination == .tags)
    }

    @Test("Lyrics Editor targets the exact current track")
    func editorTarget() throws {
        let model = CadenceAppModel()
        let currentTrack = try #require(model.currentTrack)
        model.presentNowPlaying()

        #expect(model.presentLyricsEditor())
        #expect(model.playbackWorkspace == .lyricsEditor)
        #expect(model.lyricDraft?.trackID == currentTrack.id)
        #expect(!model.isLyricDraftDirty)
    }

    @Test("Dirty editor Back supports Cancel and Discard")
    func dirtyBackGuard() throws {
        let model = CadenceAppModel()
        model.presentNowPlaying()
        model.presentLyricsEditor()
        let lineID = try #require(model.lyricDraft?.lines.first?.id)
        model.updateLyricText(lineID: lineID, text: "Changed")

        model.requestCloseLyricsEditor()

        #expect(model.pendingLyricsTransition == .closeEditor)
        #expect(model.playbackWorkspace == .lyricsEditor)

        #expect(model.resolvePendingLyricsTransition(.cancel))
        #expect(model.playbackWorkspace == .lyricsEditor)
        #expect(model.isLyricDraftDirty)

        model.requestCloseLyricsEditor()
        #expect(model.resolvePendingLyricsTransition(.discard))
        #expect(model.playbackWorkspace == .nowPlaying)
        #expect(model.lyricDraft == nil)
    }

    @Test("Save commits a lyric draft before navigation")
    func saveBeforeDestination() throws {
        let model = CadenceAppModel()
        let track = try #require(model.currentTrack)
        model.presentNowPlaying()
        model.presentLyricsEditor()
        let lineID = try #require(model.lyricDraft?.lines.first?.id)
        model.updateLyricText(lineID: lineID, text: "Saved change")

        model.requestNavigationDestination(.tags)

        #expect(model.pendingLyricsTransition == .destination(.tags))
        #expect(model.resolvePendingLyricsTransition(.save))
        #expect(model.selectedDestination == .tags)
        #expect(model.playbackWorkspace == .hidden)
        #expect(model.lyricDocuments[track.id]?.lines.first?.text == "Saved change")
    }

    @Test("Dirty editor defers queue traversal until resolution")
    func trackChangeGuard() throws {
        let model = CadenceAppModel()
        let tracks = Array(model.tracks.prefix(3))
        let first = try #require(tracks.first)
        model.startPlaybackQueue(
            source: .adHoc,
            trackIDs: tracks.map(\.id),
            startingAt: first.id
        )
        model.presentNowPlaying()
        model.presentLyricsEditor()
        let lineID = try #require(model.lyricDraft?.lines.first?.id)
        model.updateLyricText(lineID: lineID, text: "Unsaved")

        model.selectNextTrack()

        #expect(model.currentTrackID == first.id)
        #expect(model.pendingLyricsTransition == .playbackOffset(1))

        #expect(model.resolvePendingLyricsTransition(.discard))
        #expect(model.currentTrackID == tracks[1].id)
        #expect(model.playbackWorkspace == .lyricsEditor)
        #expect(model.lyricDraft?.trackID == tracks[1].id)
    }

    @Test("Bottom-player Queue respects a dirty lyric draft")
    func queueEntryGuard() throws {
        let model = CadenceAppModel()
        model.presentNowPlaying()
        model.presentLyricsEditor()
        let lineID = try #require(model.lyricDraft?.lines.first?.id)
        model.updateLyricText(lineID: lineID, text: "Unsaved")

        #expect(model.presentPlaybackQueue())
        #expect(
            model.pendingLyricsTransition
                == .nowPlayingPanel(.queue)
        )
        #expect(model.playbackWorkspace == .lyricsEditor)

        #expect(model.resolvePendingLyricsTransition(.cancel))
        #expect(model.playbackWorkspace == .lyricsEditor)

        model.presentPlaybackQueue()
        #expect(model.resolvePendingLyricsTransition(.discard))
        #expect(model.playbackWorkspace == .nowPlaying)
        #expect(model.selectedNowPlayingPanel == .queue)
        #expect(model.lyricDraft == nil)
    }
}
