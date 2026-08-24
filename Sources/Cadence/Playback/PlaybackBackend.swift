import Foundation

struct PlaybackBackendLoadRequest: Sendable {
    let current: ResolvedPlaybackTrack
    let next: ResolvedPlaybackTrack?
    let startTime: TimeInterval
    let autoplay: Bool
    let volume: Float
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
    func play()
    func pause()
    func seek(to time: TimeInterval) async throws
    func setVolume(_ volume: Float)
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

    func resetBassAnalysis() {}
}

/// Resolves stable catalog or transient queue identities into playable media.
///
/// Implementations preserve request order and omit identities that no longer
/// resolve; they never reorder or synthesize queue entries.
@MainActor
protocol PlaybackTrackResolving: AnyObject {
    func resolve(trackIDs: [UUID]) async throws -> [ResolvedPlaybackTrack]
}
