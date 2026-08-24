import Foundation

struct NowPlayingMetadataBadges: Equatable, Sendable {
    let audioQuality: AudioQualityPresentation?
    let showsSynchronizedLyrics: Bool

    static func resolve(
        audioPath: AudioPathSnapshot?,
        currentTrackID: UUID,
        lyricDocument: LyricDocument?
    ) -> Self {
        Self(
            audioQuality: audioPath.map(AudioQualityPresentation.init),
            showsSynchronizedLyrics: lyricDocument?.trackID
                == .managed(currentTrackID)
                && lyricDocument?.timingStatus == .synchronized
        )
    }
}
