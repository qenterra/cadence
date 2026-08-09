import AVFoundation
@testable import Cadence
import Testing

@MainActor
struct NativePlaybackBackendTests {
    @Test("Native timeline advances only while AVPlayer is playing")
    func timelineRateFollowsPlayerStatus() {
        #expect(
            NativePlaybackBackend.timelineRate(
                playerRate: 1,
                status: .playing
            ) == 1
        )
        #expect(
            NativePlaybackBackend.timelineRate(
                playerRate: 1,
                status: .waitingToPlayAtSpecifiedRate
            ) == 0
        )
        #expect(
            NativePlaybackBackend.timelineRate(
                playerRate: 0,
                status: .paused
            ) == 0
        )
    }
}
