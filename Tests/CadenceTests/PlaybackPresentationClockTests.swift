@testable import Cadence
import Foundation
import Testing

struct PlaybackPresentationClockTests {
    @Test("Presentation time advances from a timestamped backend sample")
    func advancesFromBackendSample() {
        var clock = PlaybackPresentationClock()

        clock.update(
            PlaybackTimelineSample(
                mediaTime: 40,
                hostUptime: 100,
                rate: 1
            )
        )

        #expect(
            abs(
                clock.time(
                    atHostUptime: 100.2,
                    duration: 200
                ) - 40.2
            ) < 0.000_001
        )
    }

    @Test("A zero-rate sample freezes presentation time")
    func zeroRateFreezesTimeline() {
        var clock = PlaybackPresentationClock()

        clock.update(
            PlaybackTimelineSample(
                mediaTime: 40.2,
                hostUptime: 100.2,
                rate: 0
            )
        )

        #expect(
            clock.time(
                atHostUptime: 101,
                duration: 200
            ) == 40.2
        )
    }

    @Test("Presentation time stays inside the playable duration")
    func clampsTimeline() {
        var clock = PlaybackPresentationClock()
        clock.update(
            PlaybackTimelineSample(
                mediaTime: -2,
                hostUptime: 100,
                rate: 1
            )
        )
        #expect(clock.time(atHostUptime: 100, duration: 200) == 0)

        clock.update(
            PlaybackTimelineSample(
                mediaTime: 199.9,
                hostUptime: 100,
                rate: 1
            )
        )
        #expect(clock.time(atHostUptime: 101, duration: 200) == 200)
    }
}
