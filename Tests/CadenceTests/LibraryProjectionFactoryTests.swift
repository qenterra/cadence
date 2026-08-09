@testable import Cadence
import Foundation
import Testing

struct LibraryProjectionFactoryTests {
    @Test("Only valid fully synchronized lyrics receive the LRC badge")
    func synchronizedLyricsBadge() {
        let synchronized = makeTrack(timing: .synchronized, parsing: .valid)
        let partial = makeTrack(timing: .partiallySynchronized, parsing: .valid)
        let malformed = makeTrack(timing: .synchronized, parsing: .malformed)

        #expect(LibraryProjectionFactory.track(synchronized).hasSynchronizedLyrics)
        #expect(!LibraryProjectionFactory.track(partial).hasSynchronizedLyrics)
        #expect(!LibraryProjectionFactory.track(malformed).hasSynchronizedLyrics)
    }

    private func makeTrack(
        timing: LyricTimingStatus,
        parsing: StoredLyricParsingStatus
    ) -> TrackRecord {
        let track = TrackRecord(
            originalFilename: "track.flac",
            title: "Track",
            duration: 120,
            codec: "FLAC",
            container: "flac",
            sampleRate: 48000,
            channelCount: 2,
            contentHash: String(repeating: "a", count: 64),
            relativeMediaPath: "Media/track.flac",
            importSessionID: UUID()
        )
        track.lyrics = LyricRecord(
            relativePath: "Lyrics/track.lrc",
            parsingStatus: parsing,
            contentHash: String(repeating: "b", count: 64),
            timingStatus: timing,
            track: track
        )
        return track
    }
}
