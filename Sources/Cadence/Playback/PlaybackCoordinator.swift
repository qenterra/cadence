import Foundation
import Observation

@MainActor
@Observable
final class PlaybackCoordinator {
    let resolver: any PlaybackTrackResolving
    let backends: [PlaybackBackendKind: any PlaybackBackend]
    let systemMediaSession: any SystemMediaSessionControlling
    let audioRouteProvider: any AudioRouteProviding
    let qualityProfileStore: any AudioQualityProfileStoring
    var resolvedTracks: [UUID: ResolvedPlaybackTrack] = [:]
    var failedTrackIDs: Set<UUID> = []
    var canonicalOrder: [UUID] = []
    var loadGeneration = 0
    var routeGeneration = 0
    var pendingOutputRoute: AudioRouteSnapshot?
    var routeFailureIsActive = false
    @ObservationIgnored
    var routeTransitionTask: Task<Void, Never>?

    var state = PlaybackCoordinatorState()
    var qualityProfile: AudioQualityProfile = .adaptive
    var repeatMode: RepeatMode = .off
    private(set) var volume: Float = 0.72

    var outputRoute: AudioRouteSnapshot = .unknown
    var stereoSpatializationEnabled = false

    init(
        resolver: any PlaybackTrackResolving,
        backends: [any PlaybackBackend],
        systemMediaSession: any SystemMediaSessionControlling =
            NoOpSystemMediaSession(),
        audioRouteProvider: any AudioRouteProviding =
            StaticAudioRouteProvider(),
        qualityProfileStore: any AudioQualityProfileStoring =
            VolatileAudioQualityProfileStore()
    ) {
        self.resolver = resolver
        self.backends = Dictionary(
            uniqueKeysWithValues: backends.map { ($0.kind, $0) }
        )
        self.systemMediaSession = systemMediaSession
        self.audioRouteProvider = audioRouteProvider
        self.qualityProfileStore = qualityProfileStore
        qualityProfile = qualityProfileStore.load()
        stereoSpatializationEnabled =
            qualityProfileStore.loadStereoSpatializationEnabled()

        for backend in backends {
            backend.onEvent = { [weak self] event in
                self?.receive(event, from: backend.kind)
            }
        }
    }

    func activateSystemMediaSession() {
        systemMediaSession.activate { [weak self] command in
            self?.perform(command)
        }
        audioRouteProvider.startMonitoring { [weak self] route in
            self?.receiveAudioRoute(route)
        }
    }

    var isPlaying: Bool {
        state.isPlaying
    }

    var progress: Double {
        state.progress
    }

    var isShuffleEnabled: Bool {
        state.queue?.isShuffled ?? false
    }

    @discardableResult
    func startQueue(
        source: PlaybackQueueSource,
        trackIDs: [UUID],
        startingAt trackID: UUID? = nil,
        isShuffled: Bool = false
    ) async -> Bool {
        activateSystemMediaSession()
        let queue = PlaybackQueueState(
            source: source,
            orderedTrackIDs: trackIDs,
            startingAt: trackID,
            isShuffled: isShuffled
        )
        guard queue.currentTrackID != nil else {
            return false
        }

        stop(resetQueue: false)
        canonicalOrder = queue.orderedTrackIDs
        state.queue = queue
        failedTrackIDs = []
        return await loadCurrent(startTime: 0, autoplay: true)
    }

    func play() {
        guard state.currentTrack != nil else {
            return
        }
        if routeFailureIsActive {
            retryAudioRouteAndPlay()
            return
        }
        activeBackend?.play()
        state.transport = .playing
        publishState()
    }

    func pause() {
        guard state.currentTrack != nil else {
            return
        }
        activeBackend?.pause()
        state.transport = .paused
        publishState()
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) async {
        await waitForAudioRouteTransitions()
        guard state.currentTrack != nil else {
            return
        }
        let clampedTime = min(max(time, 0), state.duration)
        do {
            try await activeBackend?.seek(to: clampedTime)
            state.currentTime = clampedTime
            publishState()
        } catch {
            failCurrent(with: error)
        }
    }

    func seek(toProgress progress: Double) async {
        await seek(to: state.duration * min(max(progress, 0), 1))
    }

    func next() async {
        await move(by: 1, reason: .manual)
    }

    func previous() async {
        if state.currentTime > 3 {
            await seek(to: 0)
        } else {
            await move(by: -1, reason: .manual)
        }
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
        publishState()
    }

    func setShuffleEnabled(_ enabled: Bool) {
        guard var queue = state.queue,
              let currentTrackID = queue.currentTrackID
        else {
            return
        }

        if enabled {
            var generator = SystemRandomNumberGenerator()
            queue.setShuffled(true, using: &generator)
        } else {
            queue.replaceOrder(canonicalOrder, currentTrackID: currentTrackID)
            var generator = SystemRandomNumberGenerator()
            queue.setShuffled(false, using: &generator)
        }
        state.queue = queue
        publishState()
        Task {
            await prepareFollowingTrack()
        }
    }

    func setQualityProfile(_ profile: AudioQualityProfile) async {
        await waitForAudioRouteTransitions()
        guard profile != qualityProfile else {
            return
        }
        let previousProfile = qualityProfile
        qualityProfile = profile
        qualityProfileStore.save(profile)
        guard let currentTrack = state.currentTrack else {
            return
        }
        let requestedKind = routeBackend(for: currentTrack)
        guard requestedKind != state.activeBackend else {
            publishState()
            return
        }
        guard await transitionBackend(to: requestedKind) else {
            qualityProfile = previousProfile
            qualityProfileStore.save(previousProfile)
            return
        }
    }

    func setStereoSpatializationEnabled(_ enabled: Bool) async {
        await waitForAudioRouteTransitions()
        guard enabled != stereoSpatializationEnabled else {
            return
        }
        let previousValue = stereoSpatializationEnabled
        stereoSpatializationEnabled = enabled
        qualityProfileStore.saveStereoSpatializationEnabled(enabled)
        guard
            qualityProfile == .immersive,
            let currentTrack = state.currentTrack
        else {
            publishState()
            return
        }
        let requestedKind = routeBackend(for: currentTrack)
        guard requestedKind != state.activeBackend else {
            publishState()
            return
        }
        guard await transitionBackend(to: requestedKind) else {
            stereoSpatializationEnabled = previousValue
            qualityProfileStore.saveStereoSpatializationEnabled(previousValue)
            return
        }
    }

    func stop(resetQueue: Bool = true) {
        backends.values.forEach { $0.stop() }
        loadGeneration += 1
        routeGeneration += 1
        pendingOutputRoute = nil
        routeFailureIsActive = false
        state.transport = .idle
        state.currentTrack = nil
        state.currentTime = 0
        state.duration = 0
        state.activeBackend = nil
        state.audioPath = nil
        state.failure = nil
        resolvedTracks = [:]
        if resetQueue {
            state.queue = nil
            canonicalOrder = []
        }
        systemMediaSession.clear()
    }

    func shutdown() {
        audioRouteProvider.stopMonitoring()
        routeGeneration += 1
        pendingOutputRoute = nil
        routeTransitionTask?.cancel()
        backends.values.forEach { $0.stop() }
        systemMediaSession.shutdown()
    }

    var activeBackend: (any PlaybackBackend)? {
        state.activeBackend.flatMap { backends[$0] }
    }
}

extension PlaybackCoordinator {
    func setVolume(_ requestedVolume: Float) {
        let clampedVolume = min(max(requestedVolume, 0), 1)
        guard clampedVolume != volume else {
            return
        }
        volume = clampedVolume
        activeBackend?.setVolume(clampedVolume)
    }
}
