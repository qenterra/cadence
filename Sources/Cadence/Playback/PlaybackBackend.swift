import Foundation

struct PlaybackBackendLoadRequest: Sendable {
    let current: ResolvedPlaybackTrack
    let next: ResolvedPlaybackTrack?
    let startTime: TimeInterval
    let autoplay: Bool
    let volume: Float
    let replayGainDecibels: Double?
}

enum PlaybackBackendEvent: Sendable {
    case duration(TimeInterval)
    case failed(PlaybackFailure)
    case finished(trackID: UUID, successorStarted: UUID?)
    case timeline(PlaybackTimelineSample)
    case time(TimeInterval)
}

@MainActor
protocol PlaybackBackend: AnyObject {
    var kind: PlaybackBackendKind { get }
    var onEvent: ((PlaybackBackendEvent) -> Void)? { get set }

    func load(_ request: PlaybackBackendLoadRequest) async throws
    func prepareNext(_ track: ResolvedPlaybackTrack?) async throws
    func play()
    func pause()
    func seek(to time: TimeInterval) async throws
    func setVolume(_ volume: Float)
    func setReplayGain(_ decibels: Double?)
    func setPresentationGain(
        _ gain: Float,
        duration: Duration
    ) async
    func stop()
}

extension PlaybackBackend {
    func setReplayGain(_: Double?) {}

    func setPresentationGain(
        _: Float,
        duration _: Duration
    ) async {}
}

@MainActor
protocol PlaybackTrackResolving: AnyObject {
    func resolve(trackIDs: [UUID]) async throws -> [ResolvedPlaybackTrack]
}
