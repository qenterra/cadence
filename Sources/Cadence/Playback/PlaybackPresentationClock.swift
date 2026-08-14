import Foundation

struct PlaybackTimelineSample: Equatable, Sendable {
    let mediaTime: TimeInterval
    let hostUptime: TimeInterval
    let rate: Double
}

struct PlaybackPresentationClock: Sendable {
    private(set) var anchorMediaTime: TimeInterval = 0
    private(set) var anchorHostUptime: TimeInterval = 0
    private(set) var rate: Double = 0

    mutating func update(
        _ sample: PlaybackTimelineSample
    ) {
        anchorMediaTime = max(sample.mediaTime, 0)
        anchorHostUptime = sample.hostUptime
        rate = max(sample.rate, 0)
    }

    func time(
        atHostUptime hostUptime: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        let elapsed = max(hostUptime - anchorHostUptime, 0) * rate
        return min(
            max(anchorMediaTime + elapsed, 0),
            max(duration, 0)
        )
    }
}
