import AVFoundation
import Foundation

struct PlaybackBackendLoadRequest: Sendable {
    let current: ResolvedPlaybackTrack
    let next: ResolvedPlaybackTrack?
    let startTime: TimeInterval
    let autoplay: Bool
    let volume: Float
    let normalizationGain: Float
    let nextNormalizationGain: Float
    let crossfadeDuration: TimeInterval

    init(
        current: ResolvedPlaybackTrack,
        next: ResolvedPlaybackTrack?,
        startTime: TimeInterval,
        autoplay: Bool,
        volume: Float,
        normalizationGain: Float = 1,
        nextNormalizationGain: Float = 1,
        crossfadeDuration: TimeInterval = 0
    ) {
        self.current = current
        self.next = next
        self.startTime = startTime
        self.autoplay = autoplay
        self.volume = volume
        self.normalizationGain = normalizationGain
        self.nextNormalizationGain = nextNormalizationGain
        self.crossfadeDuration = max(crossfadeDuration, 0)
    }
}

struct PlaybackBackendPreparationRequest: Sendable {
    let track: ResolvedPlaybackTrack?
    let normalizationGain: Float
    let crossfadeDuration: TimeInterval

    init(
        track: ResolvedPlaybackTrack?,
        normalizationGain: Float = 1,
        crossfadeDuration: TimeInterval = 0
    ) {
        self.track = track
        self.normalizationGain = normalizationGain
        self.crossfadeDuration = max(crossfadeDuration, 0)
    }
}

enum PlaybackBackendEvent: Sendable {
    case duration(TimeInterval)
    case failed(PlaybackFailure)
    case finished(trackID: UUID, successorStarted: UUID?)
    case timeline(PlaybackTimelineSample)
    case time(TimeInterval)
}

enum PlaybackStartFailure: Equatable, Sendable {
    case engineStopped
    case nodeStopped
    case renderTimeUnavailable
    case renderDidNotAdvance
    case staleGeneration
}

enum PlaybackStartObservation: Equatable, Sendable {
    case started
    case failed(PlaybackStartFailure)
}

/// A concrete audio renderer controlled exclusively by ``PlaybackCoordinator``.
///
/// Backends must emit state changes through ``onEvent`` and must not advance the
/// queue themselves. `load` replaces the currently prepared item, while
/// `prepareNext` is only a scheduling hint for a coordinator-owned successor.
@MainActor
protocol PlaybackBackend: AnyObject {
    var kind: PlaybackBackendKind { get }
    var onEvent: ((PlaybackBackendEvent) -> Void)? { get set }
    var bassLevelProvider: (any PlaybackBassLevelProviding)? { get }

    func load(_ request: PlaybackBackendLoadRequest) async throws
    func verifyStart(timeout: Duration) async -> PlaybackStartObservation
    func prepareNext(_ track: ResolvedPlaybackTrack?) async throws
    func prepareNext(_ request: PlaybackBackendPreparationRequest) async throws
    func play()
    func play(fadeInDuration: Duration)
    func pause()
    func seek(to time: TimeInterval) async throws
    func setVolume(_ volume: Float)
    func setNormalizationGain(_ gain: Float)
    func setPresentationGain(
        _ gain: Float,
        duration: Duration
    ) async
    func resetBassAnalysis()
    func stop()
}

extension PlaybackBackend {
    var bassLevelProvider: (any PlaybackBassLevelProviding)? {
        nil
    }

    func setPresentationGain(
        _: Float,
        duration _: Duration
    ) async {}

    func prepareNext(
        _ request: PlaybackBackendPreparationRequest
    ) async throws {
        try await prepareNext(request.track)
    }

    func play(fadeInDuration _: Duration) {
        play()
    }

    func setNormalizationGain(_: Float) {}

    func resetBassAnalysis() {}
}

@MainActor
protocol PlaybackAirPlayPlayerProviding: AnyObject {
    var airPlayPlayer: AVPlayer? { get }
}

/// Resolves stable catalog or transient queue identities into playable media.
///
/// Implementations preserve request order and omit identities that no longer
/// resolve; they never reorder or synthesize queue entries.
@MainActor
protocol PlaybackTrackResolving: AnyObject {
    func resolve(trackIDs: [UUID]) async throws -> [ResolvedPlaybackTrack]
}
