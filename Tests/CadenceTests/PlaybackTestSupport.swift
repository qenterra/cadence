@testable import Cadence
import Foundation

@MainActor
final class PlaybackTestResolver: PlaybackTrackResolving {
    var tracks: [UUID: ResolvedPlaybackTrack]
    var unavailableIDs: Set<UUID> = []
    private(set) var requests: [[UUID]] = []

    init(tracks: [ResolvedPlaybackTrack]) {
        self.tracks = Dictionary(
            uniqueKeysWithValues: tracks.map { ($0.track.id, $0) }
        )
    }

    func resolve(
        trackIDs: [UUID]
    ) async throws -> [ResolvedPlaybackTrack] {
        requests.append(trackIDs)
        if let unavailableID = trackIDs.first(where: unavailableIDs.contains) {
            throw PlaybackFailure(
                trackID: unavailableID,
                message: "Unavailable"
            )
        }
        return trackIDs.compactMap { tracks[$0] }
    }
}

@MainActor
final class PlaybackTestBackend: PlaybackBackend {
    let kind: PlaybackBackendKind
    var onEvent: ((PlaybackBackendEvent) -> Void)?
    var loadError: Error?
    var shouldSuspendNextLoad = false
    private(set) var loadRequests: [PlaybackBackendLoadRequest] = []
    private(set) var preparedTracks: [ResolvedPlaybackTrack?] = []
    private(set) var seekTimes: [TimeInterval] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var volumes: [Float] = []
    private(set) var suspendedLoadCount = 0
    private var loadContinuations: [CheckedContinuation<Void, Never>] = []

    init(kind: PlaybackBackendKind) {
        self.kind = kind
    }

    func load(
        _ request: PlaybackBackendLoadRequest
    ) async throws {
        if let loadError {
            throw loadError
        }
        loadRequests.append(request)
        if shouldSuspendNextLoad {
            shouldSuspendNextLoad = false
            suspendedLoadCount += 1
            await withCheckedContinuation { continuation in
                loadContinuations.append(continuation)
            }
        }
    }

    func prepareNext(
        _ track: ResolvedPlaybackTrack?
    ) async throws {
        preparedTracks.append(track)
    }

    func play() {
        playCount += 1
    }

    func pause() {
        pauseCount += 1
    }

    func seek(to time: TimeInterval) async throws {
        seekTimes.append(time)
    }

    func setVolume(_ volume: Float) {
        volumes.append(volume)
    }

    func stop() {
        stopCount += 1
    }

    func emit(_ event: PlaybackBackendEvent) {
        onEvent?(event)
    }

    func resumeNextLoad() {
        guard !loadContinuations.isEmpty else {
            return
        }
        loadContinuations.removeFirst().resume()
    }
}

@MainActor
final class PlaybackTestSystemMediaSession: SystemMediaSessionControlling {
    private(set) var activationCount = 0
    private(set) var states: [PlaybackCoordinatorState] = []
    private(set) var clearCount = 0
    private var handler: ((SystemMediaCommand) -> Void)?

    func activate(
        handler: @escaping (SystemMediaCommand) -> Void
    ) {
        if self.handler == nil {
            activationCount += 1
        }
        self.handler = handler
    }

    func update(
        state: PlaybackCoordinatorState
    ) {
        states.append(state)
    }

    func clear() {
        clearCount += 1
    }

    func shutdown() {
        clearCount += 1
        handler = nil
    }

    func send(_ command: SystemMediaCommand) {
        handler?(command)
    }
}

func playbackTestTrack(
    id: UUID,
    title: String,
    codec: String = "FLAC",
    container: String = "flac",
    duration: TimeInterval = 120,
    sampleRate: Double = 48000,
    channelCount: Int = 2,
    spatialFormat: StoredSpatialFormat = .stereo
) -> ResolvedPlaybackTrack {
    ResolvedPlaybackTrack(
        track: PlaybackTrack(
            id: id,
            title: title,
            artistID: nil,
            artist: "Artist",
            albumID: nil,
            album: "Album",
            duration: duration,
            codec: codec,
            container: container,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitrate: nil,
            bitDepth: 24,
            spatialFormat: spatialFormat,
            relativeMediaPath: "Media/\(id).\(container)",
            lyricRelativePath: nil,
            artworkID: nil,
            replayGainTrackGain: nil,
            replayGainTrackPeak: nil
        ),
        mediaURL: URL(filePath: "/tmp/\(id).\(container)")
    )
}
