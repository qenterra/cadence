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
    var shouldSuspendNextSeek = false
    var simulatesAutoplayDuringLoad = false
    var loadDelay: Duration?
    var startObservations: [PlaybackStartObservation] = [.started]
    let bassMeter = PCMBassLevelMeter()
    var exposesRealtimeBass: Bool
    private(set) var loadRequests: [PlaybackBackendLoadRequest] = []
    private(set) var preparedTracks: [ResolvedPlaybackTrack?] = []
    private(set) var seekTimes: [TimeInterval] = []
    private(set) var playCount = 0
    private(set) var loadAutoplayStartCount = 0
    private(set) var verifyStartCount = 0
    private(set) var resetBassCountAtLastPlay: Int?
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var volumes: [Float] = []
    private(set) var suspendedLoadCount = 0
    private(set) var suspendedSeekCount = 0
    private(set) var resetBassCount = 0
    private var loadContinuations: [CheckedContinuation<Void, Never>] = []
    private var seekContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        kind: PlaybackBackendKind,
        exposesRealtimeBass: Bool? = nil
    ) {
        self.kind = kind
        self.exposesRealtimeBass = exposesRealtimeBass ?? (kind == .pcm)
    }

    var bassLevelProvider: (any PlaybackBassLevelProviding)? {
        exposesRealtimeBass ? bassMeter : nil
    }

    func load(
        _ request: PlaybackBackendLoadRequest
    ) async throws {
        if let loadError {
            throw loadError
        }
        loadRequests.append(request)
        if request.autoplay, simulatesAutoplayDuringLoad {
            loadAutoplayStartCount += 1
            play()
        }
        if let loadDelay {
            try await Task.sleep(for: loadDelay)
        }
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

    func verifyStart(
        timeout _: Duration
    ) async -> PlaybackStartObservation {
        verifyStartCount += 1
        guard !startObservations.isEmpty else {
            return .started
        }
        return startObservations.removeFirst()
    }

    func play() {
        resetBassCountAtLastPlay = resetBassCount
        playCount += 1
    }

    func pause() {
        pauseCount += 1
    }

    func seek(to time: TimeInterval) async throws {
        seekTimes.append(time)
        if shouldSuspendNextSeek {
            shouldSuspendNextSeek = false
            suspendedSeekCount += 1
            await withCheckedContinuation { continuation in
                seekContinuations.append(continuation)
            }
        }
    }

    func setVolume(_ volume: Float) {
        volumes.append(volume)
    }

    func stop() {
        stopCount += 1
    }

    func resetBassAnalysis() {
        resetBassCount += 1
        bassMeter.resetPublication()
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

    func resumeNextSeek() {
        guard !seekContinuations.isEmpty else {
            return
        }
        seekContinuations.removeFirst().resume()
    }
}

actor PlaybackTestBassEnvelopeLoader {
    private(set) var requestedURLs: [URL] = []
    private var continuations: [
        CheckedContinuation<PlaybackBassEnvelope?, Never>
    ] = []

    func load(_ url: URL) async -> PlaybackBassEnvelope? {
        requestedURLs.append(url)
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func requestCount() -> Int {
        requestedURLs.count
    }

    func resumeNext(with envelope: PlaybackBassEnvelope?) {
        guard !continuations.isEmpty else {
            return
        }
        continuations.removeFirst().resume(returning: envelope)
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

@MainActor
final class PlaybackTestAudioRouteProvider: AudioRouteProviding {
    private var route: AudioRouteSnapshot
    private var changeHandler: AudioRouteChangeHandler?
    private(set) var monitoringStartCount = 0
    private(set) var monitoringStopCount = 0

    init(route: AudioRouteSnapshot = .unknown) {
        self.route = route
    }

    func currentRoute() -> AudioRouteSnapshot {
        route
    }

    func startMonitoring(
        _ handler: @escaping AudioRouteChangeHandler
    ) {
        if changeHandler == nil {
            monitoringStartCount += 1
        }
        changeHandler = handler
    }

    func stopMonitoring() {
        if changeHandler != nil {
            monitoringStopCount += 1
        }
        changeHandler = nil
    }

    func emit(_ route: AudioRouteSnapshot) {
        self.route = route
        changeHandler?(route)
    }

    func setCurrentRouteWithoutNotification(
        _ route: AudioRouteSnapshot
    ) {
        self.route = route
    }
}

@MainActor
func makePlaybackCoordinator(
    resolver: any PlaybackTrackResolving,
    backends: [any PlaybackBackend],
    systemMediaSession: any SystemMediaSessionControlling =
        PlaybackTestSystemMediaSession(),
    audioRouteProvider: any AudioRouteProviding =
        PlaybackTestAudioRouteProvider(),
    bassEnvelopeLoader: @escaping PlaybackBassEnvelopeLoading =
        defaultPlaybackBassEnvelopeLoader
) -> PlaybackCoordinator {
    PlaybackCoordinator(
        resolver: resolver,
        backends: backends,
        systemMediaSession: systemMediaSession,
        audioRouteProvider: audioRouteProvider,
        bassEnvelopeLoader: bassEnvelopeLoader
    )
}

func waitForBassEnvelopeRequests(
    _ expectedCount: Int,
    loader: PlaybackTestBassEnvelopeLoader
) async -> Bool {
    for _ in 0 ..< 100 {
        if await loader.requestCount() >= expectedCount {
            return true
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return false
}

func playbackTestBassEnvelope(
    level: Float,
    duration: Int = 180
) -> PlaybackBassEnvelope {
    PlaybackBassEnvelope(
        samplesPerSecond: 1,
        levels: Array(repeating: level, count: duration + 1)
    )
}

@MainActor
func waitForBassLevel(
    _ expectedLevel: Float,
    coordinator: PlaybackCoordinator
) async -> Bool {
    for _ in 0 ..< 100 {
        if abs(coordinator.currentBassLevel() - expectedLevel) < 0.000_001 {
            return true
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return false
}

func playbackTestTrack(
    id: UUID,
    title: String,
    codec: String = "FLAC",
    container: String = "flac",
    duration: TimeInterval = 120,
    sampleRate: Double = 48000,
    channelCount: Int = 2,
    spatialFormat: StoredSpatialFormat = .stereo,
    replayGainTrackGain: Double? = nil,
    artworkID: UUID? = nil
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
            artworkID: artworkID,
            replayGainTrackGain: replayGainTrackGain,
            replayGainTrackPeak: nil
        ),
        mediaURL: URL(filePath: "/tmp/\(id).\(container)")
    )
}

@MainActor
final class CadenceModeVisualReadinessTracker {
    private var artworkReadyTrackIDs: Set<UUID> = []
    private var latestSnapshot: CadenceModeArtworkRenderSnapshot?
    private var firstAcceptedSnapshots: [
        UUID: CadenceModeArtworkRenderSnapshot
    ] = [:]

    lazy var observer = CadenceModeVisualReadinessObserver(
        artworkReady: { [weak self] trackID in
            self?.artworkReadyTrackIDs.insert(trackID)
        },
        render: { [weak self] snapshot in
            self?.latestSnapshot = snapshot
            guard snapshot.artworkFrame.width > 0,
                  snapshot.artworkFrame.height > 0,
                  self?.firstAcceptedSnapshots[snapshot.trackID] == nil else {
                return
            }
            self?.firstAcceptedSnapshots[snapshot.trackID] = snapshot
        }
    )

    func waitUntilReady(
        trackID: UUID,
        expectedArtworkScale: ClosedRange<CGFloat>
    ) async throws -> CadenceModeArtworkRenderSnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            if artworkReadyTrackIDs.contains(trackID),
               let latestSnapshot,
               latestSnapshot.trackID == trackID,
               latestSnapshot.artworkFrame.width > 0,
               latestSnapshot.artworkFrame.height > 0,
               expectedArtworkScale.contains(latestSnapshot.artworkScale) {
                return latestSnapshot
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CadenceModeScreenshotError.visualReadinessTimedOut
    }

    func waitForFirstAcceptedRender(
        trackID: UUID
    ) async throws -> CadenceModeArtworkRenderSnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            if let snapshot = firstAcceptedSnapshots[trackID] {
                return snapshot
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CadenceModeScreenshotError.visualReadinessTimedOut
    }
}
