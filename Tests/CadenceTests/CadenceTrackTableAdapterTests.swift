import AppKit
@testable import Cadence
import QenTerraMediaComponents
import Testing

struct CadenceTrackTableAdapterTests {
    @Test @MainActor func trackRowMapsLiteralStateAndLiveNativeEnvironment() {
        let id = UUID()
        let artworkID = UUID()
        let row = TrackRowDisplayProjection(
            track: LibraryTrackProjection(
                id: id, title: "Synthetic Track", artistID: nil, artist: "Creator",
                albumID: nil, album: "Collection", duration: 222, year: 2026,
                codec: "FLAC", sampleRate: 44100, channelCount: 2, bitDepth: 24,
                isFavorite: true, isExplicit: true, customArtworkID: nil, artworkID: artworkID,
                relativeMediaPath: "fixture.flac", lastPlayedAt: nil, hasSynchronizedLyrics: true
            ), isCurrentTrack: true, isPlaying: true
        )
        let presentation = CadenceTrackTableAdapter.presentation(for: row)
        #expect(presentation.id == id)
        #expect(presentation.title == "Synthetic Track")
        #expect(presentation.creator == row.artist && presentation.collection == row.album)
        #expect(presentation.duration == "3:42")
        #expect(presentation.artworkIdentity == artworkID.uuidString)
        #expect(presentation.isCurrent && presentation.isPlaying && presentation.isFavorite)
        let view = NSView()
        view.appearance = NSAppearance(named: .aqua)
        #expect(
            CadenceTrackTableAdapter.environment(
                for: view,
                density: .compact,
                reduceMotion: true
            ).appearance == .light
        )
        view.appearance = NSAppearance(named: .darkAqua)
        let native = CadenceTrackTableAdapter.environment(for: view, density: .compact, reduceMotion: true)
        #expect(native.appearance == .dark && native.reducesMotion && native.density == .compact)
        let typography = CadenceTrackTableAdapter.typography(.large)
        #expect(typography.primaryPointSize == 15 && typography.secondaryPointSize == 14)
        #expect(typography.badgeRole.size == 9 && typography.badgeRole.weight == 700)
        #expect(typography.durationRole.weight == 400)
        #expect(CadenceTrackTableAdapter.columns([.album, .time]) == [.collection, .duration])
    }
}
