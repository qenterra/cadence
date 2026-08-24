@testable import Cadence
import Foundation
import Testing

struct NowPlayingMetadataBadgesTests {
    @Test("Only a synchronized document for the current track shows LRC")
    func synchronizedLyricsBadge() {
        let trackID = UUID()

        #expect(!badges(trackID: trackID, document: nil).showsSynchronizedLyrics)
        #expect(!badges(
            trackID: trackID,
            document: document(trackID: trackID, times: [nil, nil])
        ).showsSynchronizedLyrics)
        #expect(!badges(
            trackID: trackID,
            document: document(trackID: trackID, times: [0, nil])
        ).showsSynchronizedLyrics)
        #expect(badges(
            trackID: trackID,
            document: document(trackID: trackID, times: [0, 10])
        ).showsSynchronizedLyrics)
    }

    @Test("A stale accepted document cannot badge the next track")
    func staleTrackDocument() {
        let currentTrackID = UUID()
        let staleDocument = document(
            trackID: UUID(),
            times: [0, 10]
        )

        #expect(!badges(
            trackID: currentTrackID,
            document: staleDocument
        ).showsSynchronizedLyrics)
    }

    @Test("The format presentation remains available beside LRC")
    func formatPresentation() {
        let trackID = UUID()
        let presentation = badges(
            trackID: trackID,
            document: document(trackID: trackID, times: [0])
        )

        #expect(presentation.audioQuality?.badge == "FLAC · 24-bit · 96 kHz")
        #expect(presentation.showsSynchronizedLyrics)
    }

    private func badges(
        trackID: UUID,
        document: LyricDocument?
    ) -> NowPlayingMetadataBadges {
        NowPlayingMetadataBadges.resolve(
            audioPath: AudioPathSnapshot(
                codec: "flac",
                container: "flac",
                sourceBitDepth: 24,
                sourceSampleRate: 96000,
                sourceChannelCount: 2,
                sourceSpatialFormat: .stereo,
                backend: .pcm,
                rendererSampleRate: 96000,
                rendererChannelCount: 2,
                outputRoute: .unknown,
                nextTransitionIsGapless: true
            ),
            currentTrackID: trackID,
            lyricDocument: document
        )
    }

    private func document(
        trackID: UUID,
        times: [TimeInterval?]
    ) -> LyricDocument {
        LyricDocument(
            trackID: trackID,
            lines: times.enumerated().map { index, time in
                LyricLine(text: "Line \(index)", startTime: time)
            }
        )
    }
}
