import AVFoundation
import Foundation
import Observation

enum PlaybackIntentTransport: Equatable, Sendable {
    case failed
    case idle
    case paused
    case playing

    var state: PlaybackTransportState {
        switch self {
        case .failed:
            .failed
        case .idle:
            .idle
        case .paused:
            .paused
        case .playing:
            .playing
        }
    }

    var shouldAutoplay: Bool {
        self == .playing
    }
}

struct PlaybackIntentAuthority: Equatable, Sendable {
    let generation: Int
    let currentItemID: UUID?
    let transport: PlaybackIntentTransport
}

struct PlaybackRouteFailureAuthority: Equatable, Sendable {
    let failure: PlaybackFailure
    let currentItemID: UUID
    let requestedRoute: AudioRouteSnapshot
    let routeGeneration: Int
    let failureGeneration: Int
}

@MainActor
@Observable
final class PlaybackCoordinator {
    let resolver: any PlaybackTrackResolving
    let backends: [PlaybackBackendKind: any PlaybackBackend]
    let systemMediaSession: any SystemMediaSessionControlling
    let audioRouteProvider: any AudioRouteProviding
    let notificationController: CadenceNotificationController?
    let preferences: UserDefaults
    let playbackSessionStore: PlaybackSessionStore
    let persistsPlaybackSession: Bool
    var resolvedTracks: [UUID: ResolvedPlaybackTrack] = [:]
    var failedTrackIDs: Set<UUID> = []
    var canonicalOrder: [UUID] = []
    var loadGeneration = 0
    var routeGeneration = 0
    var pendingOutputRoute: AudioRouteSnapshot?
    @ObservationIgnored
    var failureGeneration = 0
    @ObservationIgnored
    var routeFailureAuthority: PlaybackRouteFailureAuthority?
    @ObservationIgnored
    var routeTransitionTask: Task<Void, Never>?
    @ObservationIgnored
    var routeRecoveryShouldResume = false
    @ObservationIgnored
    var sessionRestoreAttempted = false
    @ObservationIgnored
    var playbackIntent = PlaybackIntentAuthority(
        generation: 0,
        currentItemID: nil,
        transport: .idle
    )

    var state = PlaybackCoordinatorState()
    var playbackIndicator = PlaybackIndicatorState.idle
    @ObservationIgnored
    var presentationClock = PlaybackPresentationClock()
    @ObservationIgnored
    var lastTimelinePublication: PlaybackTimelineSample?
    @ObservationIgnored
    var bassGeneration = 0
    @ObservationIgnored
    var bassEnvelopeWorker: Task<PlaybackBassEnvelope?, Never>?
    @ObservationIgnored
    var bassEnvelope: PlaybackBassEnvelope?
    @ObservationIgnored
    var bassEnvelopeTrackID: UUID?
    @ObservationIgnored
    var bassPresentationIsActive = false
    @ObservationIgnored
    var bassEnvelopeCache = PlaybackBassEnvelopeCache(capacity: 8)
    let bassEnvelopeLoader: PlaybackBassEnvelopeLoading
    var repeatMode: RepeatMode = .off
    private(set) var volume: Float = 0.72

    var outputRoute: AudioRouteSnapshot = .unknown
    init(
        resolver: any PlaybackTrackResolving,
        backends: [any PlaybackBackend],
        systemMediaSession: any SystemMediaSessionControlling,
        audioRouteProvider: any AudioRouteProviding,
        notificationController: CadenceNotificationController? = nil,
        preferences: UserDefaults = .standard,
        persistsPlaybackSession: Bool = true,
        bassEnvelopeLoader: @escaping PlaybackBassEnvelopeLoading =
            defaultPlaybackBassEnvelopeLoader
    ) {
        self.resolver = resolver
        self.backends = Dictionary(
            uniqueKeysWithValues: backends.map { ($0.kind, $0) }
        )
        self.systemMediaSession = systemMediaSession
        self.audioRouteProvider = audioRouteProvider
        self.notificationController = notificationController
        self.preferences = preferences
        playbackSessionStore = PlaybackSessionStore(defaults: preferences)
        self.persistsPlaybackSession = persistsPlaybackSession
        self.bassEnvelopeLoader = bassEnvelopeLoader

        CadencePreferences.registerDefaults(in: preferences)

        for backend in backends {
            backend.onEvent = { [weak self] event in
                self?.receive(event, from: backend.kind)
            }
        }
    }

    func activateSystemMediaSession() {
        systemMediaSession.setSkipInterval(
            CadencePreferences.seekInterval(in: preferences).seconds
        )
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
        guard state.duration > 0 else {
            return 0
        }
        return min(max(state.currentTime / state.duration, 0), 1)
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
        routeRecoveryShouldResume = false
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
        if retryableRouteFailureAuthority != nil {
            routeRecoveryShouldResume = false
            let intent = advancePlaybackIntent(
                currentItemID: state.currentTrack?.id,
                transport: .playing
            )
            retryAudioRouteAndPlay(expectedIntent: intent)
            return
        }
        guard state.failure == nil else {
            return
        }
        advancePlaybackIntent(
            currentItemID: state.currentTrack?.id,
            transport: .playing
        )
        state.transport = .playing
        activateBassSourceForCurrentTrack()
        activeBackend?.play()
        publishState()
    }

    func pause() {
        guard state.currentTrack != nil else {
            return
        }
        routeRecoveryShouldResume = false
        advancePlaybackIntent(
            currentItemID: state.currentTrack?.id,
            transport: .paused
        )
        state.currentTime = presentationTime()
        invalidateBassState()
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
        invalidateBassState()
        do {
            try await activeBackend?.seek(to: clampedTime)
            state.currentTime = clampedTime
            if state.isPlaying {
                activateBassSourceForCurrentTrack()
            }
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
        if CadencePreferences.previousTrackBehavior(in: preferences)
            == .restartCurrent,
            presentationTime() > 3 {
            await seek(to: 0)
        } else {
            await move(by: -1, reason: .manual)
        }
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

    func setRepeatMode(_ mode: RepeatMode) {
        guard repeatMode != mode else {
            return
        }
        repeatMode = mode
        persistPlaybackSession()
    }

    func stop(resetQueue: Bool = true) {
        routeRecoveryShouldResume = false
        advancePlaybackIntent(
            currentItemID: nil,
            transport: .idle
        )
        invalidateBassState()
        backends.values.forEach { $0.stop() }
        loadGeneration += 1
        routeGeneration += 1
        pendingOutputRoute = nil
        invalidateRouteFailureAuthority()
        state.transport = .idle
        state.currentTrack = nil
        state.currentTime = 0
        state.duration = 0
        state.activeBackend = nil
        state.audioPath = nil
        state.failure = nil
        lastTimelinePublication = nil
        resolvedTracks = [:]
        if resetQueue {
            state.queue = nil
            canonicalOrder = []
            if persistsPlaybackSession {
                playbackSessionStore.clear()
            }
        }
        systemMediaSession.clear()
    }

    func shutdown() {
        state.currentTime = presentationTime()
        persistPlaybackSession()
        audioRouteProvider.stopMonitoring()
        advancePlaybackIntent(
            currentItemID: nil,
            transport: .idle
        )
        routeGeneration += 1
        pendingOutputRoute = nil
        routeTransitionTask?.cancel()
        invalidateRouteFailureAuthority()
        invalidateBassState()
        backends.values.forEach { $0.stop() }
        systemMediaSession.shutdown()
    }

    var activeBackend: (any PlaybackBackend)? {
        state.activeBackend.flatMap { backends[$0] }
    }

    var airPlayPlayer: AVPlayer? {
        (backends[.native] as? NativePlaybackBackend)?.airPlayPlayer
    }

    func presentationTime(
        atHostUptime hostUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> TimeInterval {
        presentationClock.time(
            atHostUptime: hostUptime,
            duration: state.duration
        )
    }
}

extension PlaybackCoordinator {
    var visibleRouteFailureAuthority: PlaybackRouteFailureAuthority? {
        guard let authority = routeFailureAuthority,
              authority.failureGeneration == failureGeneration,
              authority.failure == state.failure,
              authority.currentItemID == state.currentTrack?.id,
              authority.currentItemID == state.queue?.currentTrackID
        else {
            return nil
        }
        return authority
    }

    var retryableRouteFailureAuthority: PlaybackRouteFailureAuthority? {
        guard let authority = visibleRouteFailureAuthority,
              authority.requestedRoute == audioRouteProvider.currentRoute(),
              authority.routeGeneration == routeGeneration
        else {
            return nil
        }
        return authority
    }

    func acceptRouteFailure(
        _ failure: PlaybackFailure,
        currentItemID: UUID,
        requestedRoute: AudioRouteSnapshot,
        routeGeneration: Int
    ) {
        failureGeneration += 1
        routeFailureAuthority = PlaybackRouteFailureAuthority(
            failure: failure,
            currentItemID: currentItemID,
            requestedRoute: requestedRoute,
            routeGeneration: routeGeneration,
            failureGeneration: failureGeneration
        )
        state.failure = failure
    }

    func clearVisibleRouteFailureAuthority(currentItemID: UUID) {
        let shouldClearFailure = visibleRouteFailureAuthority?.currentItemID
            == currentItemID
        invalidateRouteFailureAuthority()
        if shouldClearFailure {
            state.failure = nil
        }
    }

    func invalidateRouteFailureAuthority() {
        failureGeneration += 1
        routeFailureAuthority = nil
    }

    @discardableResult
    func advancePlaybackIntent(
        currentItemID: UUID?,
        transport: PlaybackIntentTransport
    ) -> PlaybackIntentAuthority {
        let next = PlaybackIntentAuthority(
            generation: playbackIntent.generation + 1,
            currentItemID: currentItemID,
            transport: transport
        )
        playbackIntent = next
        return next
    }

    func setVolume(_ requestedVolume: Float) {
        let clampedVolume = min(max(requestedVolume, 0), 1)
        guard clampedVolume != volume else {
            return
        }
        volume = clampedVolume
        activeBackend?.setVolume(clampedVolume)
    }
}
