import Foundation

struct NowPlayingMetadataBadges: Equatable, Sendable {
    let audioQuality: AudioQualityPresentation?
    let showsSynchronizedLyrics: Bool

    static func resolve(
        audioPath: AudioPathSnapshot?,
        currentTrackID: UUID,
        lyricDocument: LyricDocument?,
        showsTechnicalInformation: Bool = true
    ) -> Self {
        Self(
            audioQuality: showsTechnicalInformation
                ? audioPath.map(AudioQualityPresentation.init)
                : nil,
            showsSynchronizedLyrics: lyricDocument?.trackID
                == .managed(currentTrackID)
                && lyricDocument?.timingStatus == .synchronized
        )
    }
}
