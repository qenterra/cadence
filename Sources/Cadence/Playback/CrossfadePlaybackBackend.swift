import Foundation

/// Adds an overlapping successor renderer while preserving the coordinator as
/// the sole queue authority. With crossfade disabled, the wrapped backend keeps
/// its native gapless scheduling path unchanged.
@MainActor
final class CrossfadePlaybackBackend: PlaybackBackend {
    let kind: PlaybackBackendKind
    var onEvent: ((PlaybackBackendEvent) -> Void)?

    let primary: any PlaybackBackend
    let secondary: any PlaybackBackend
    private var activeSlot = CrossfadePlaybackSlot.primary
    private var currentTrack: ResolvedPlaybackTrack?
    private var pendingPreparation: PlaybackBackendPreparationRequest?
    private var preparedSlot: CrossfadePlaybackSlot?
    private var preparedTrackID: UUID?
    private var crossfadeDuration: TimeInterval = 0
    private var volume: Float = 0.72
    private var generation = 0
    private var isTransitioning = false
    private var preloadTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?

    init(
        kind: PlaybackBackendKind,
        primary: any PlaybackBackend,
        secondary: any PlaybackBackend
    ) {
        precondition(primary.kind == kind && secondary.kind == kind)
        self.kind = kind
        self.primary = primary
        self.secondary = secondary
        bindEvents()
    }

    func load(_ request: PlaybackBackendLoadRequest) async throws {
        generation &+= 1
        let acceptedGeneration = generation
        cancelPendingWork()
        primary.stop()
        secondary.stop()
        activeSlot = .primary
        currentTrack = request.current
        volume = request.volume
        crossfadeDuration = max(request.crossfadeDuration, 0)
        isTransitioning = false
        preparedSlot = nil
        preparedTrackID = nil
        pendingPreparation = request.next.map {
            PlaybackBackendPreparationRequest(
                track: $0,
                normalizationGain: request.nextNormalizationGain,
                crossfadeDuration: crossfadeDuration
            )
        }

        let usesCrossfade = crossfadeDuration > 0 && request.next != nil
        try await primary.load(
            PlaybackBackendLoadRequest(
                current: request.current,
                next: usesCrossfade ? nil : request.next,
                startTime: request.startTime,
                autoplay: request.autoplay,
                volume: request.volume,
                normalizationGain: request.normalizationGain
            )
        )
        guard acceptedGeneration == generation else {
            return
        }
        if usesCrossfade, let preparation = pendingPreparation {
            schedulePreload(
                preparation,
                into: .secondary,
                generation: acceptedGeneration
            )
        }
    }

    func verifyStart(timeout: Duration) async -> PlaybackStartObservation {
        await activeBackend.verifyStart(timeout: timeout)
    }

    func prepareNext(_ track: ResolvedPlaybackTrack?) async throws {
        try await prepareNext(
            PlaybackBackendPreparationRequest(
                track: track,
                crossfadeDuration: crossfadeDuration
            )
        )
    }

    func prepareNext(
        _ request: PlaybackBackendPreparationRequest
    ) async throws {
        crossfadeDuration = max(request.crossfadeDuration, 0)
        pendingPreparation = request.track == nil ? nil : request

        guard crossfadeDuration > 0 else {
            preloadTask?.cancel()
            preloadTask = nil
            preparedSlot?.backend(in: self).stop()
            preparedSlot = nil
            preparedTrackID = nil
            try await activeBackend.prepareNext(request.track)
            return
        }

        try await activeBackend.prepareNext(nil)
        guard !isTransitioning else {
            return
        }
        guard request.track != nil else {
            preloadTask?.cancel()
            preloadTask = nil
            inactiveBackend.stop()
            preparedSlot = nil
            preparedTrackID = nil
            return
        }
        schedulePreload(
            request,
            into: activeSlot.other,
            generation: generation
        )
    }

    func play() {
        activeBackend.play()
    }

    func play(fadeInDuration: Duration) {
        activeBackend.play(fadeInDuration: fadeInDuration)
    }

    func pause() {
        retireOverlapIfNeeded()
        activeBackend.pause()
    }

    func seek(to time: TimeInterval) async throws {
        let preparation = pendingPreparation
        retireOverlapIfNeeded()
        preloadTask?.cancel()
        preloadTask = nil
        inactiveBackend.stop()
        preparedSlot = nil
        preparedTrackID = nil
        try await activeBackend.seek(to: time)
        if let preparation, crossfadeDuration > 0 {
            schedulePreload(
                preparation,
                into: activeSlot.other,
                generation: generation
            )
        }
    }

    func setVolume(_ volume: Float) {
        self.volume = min(max(volume, 0), 1)
        primary.setVolume(self.volume)
        secondary.setVolume(self.volume)
    }

    func stop() {
        generation &+= 1
        cancelPendingWork()
        primary.stop()
        secondary.stop()
        currentTrack = nil
        pendingPreparation = nil
        preparedSlot = nil
        preparedTrackID = nil
        crossfadeDuration = 0
        isTransitioning = false
    }

    var activeBackend: any PlaybackBackend {
        activeSlot.backend(in: self)
    }

    private var inactiveBackend: any PlaybackBackend {
        activeSlot.other.backend(in: self)
    }
}

private extension CrossfadePlaybackBackend {
    func bindEvents() {
        primary.onEvent = { [weak self] event in
            self?.receive(event, from: .primary)
        }
        secondary.onEvent = { [weak self] event in
            self?.receive(event, from: .secondary)
        }
    }

    func receive(
        _ event: PlaybackBackendEvent,
        from slot: CrossfadePlaybackSlot
    ) {
        guard currentTrack != nil, slot == activeSlot else {
            return
        }
        onEvent?(event)
        if case let .timeline(sample) = event {
            startCrossfadeIfNeeded(sample: sample)
        }
    }

    func schedulePreload(
        _ request: PlaybackBackendPreparationRequest,
        into slot: CrossfadePlaybackSlot,
        generation acceptedGeneration: Int
    ) {
        guard let track = request.track else {
            return
        }
        preloadTask?.cancel()
        preparedSlot = nil
        preparedTrackID = nil
        let backend = slot.backend(in: self)
        backend.stop()
        let requestedVolume = volume
        preloadTask = Task { @MainActor [weak self] in
            do {
                try await backend.load(
                    PlaybackBackendLoadRequest(
                        current: track,
                        next: nil,
                        startTime: 0,
                        autoplay: false,
                        volume: requestedVolume,
                        normalizationGain: request.normalizationGain
                    )
                )
                guard let self,
                      !Task.isCancelled,
                      acceptedGeneration == generation,
                      slot != activeSlot,
                      pendingPreparation?.track?.track.id == track.track.id
                else {
                    backend.stop()
                    return
                }
                preparedSlot = slot
                preparedTrackID = track.track.id
            } catch {
                guard let self,
                      acceptedGeneration == generation,
                      slot != activeSlot
                else {
                    return
                }
                preparedSlot = nil
                preparedTrackID = nil
                backend.stop()
            }
        }
    }

    func startCrossfadeIfNeeded(sample: PlaybackTimelineSample) {
        guard sample.rate > 0,
              !isTransitioning,
              crossfadeDuration > 0,
              let currentTrack,
              let preparation = pendingPreparation,
              let successor = preparation.track,
              preparedSlot == activeSlot.other,
              preparedTrackID == successor.track.id
        else {
            return
        }
        let duration = effectiveCrossfadeDuration(
            configured: crossfadeDuration,
            currentDuration: currentTrack.track.duration,
            nextDuration: successor.track.duration
        )
        guard duration > 0,
              currentTrack.track.duration - sample.mediaTime <= duration
        else {
            return
        }
        beginCrossfade(
            predecessor: currentTrack,
            successor: successor,
            duration: duration
        )
    }

    func effectiveCrossfadeDuration(
        configured: TimeInterval,
        currentDuration: TimeInterval,
        nextDuration: TimeInterval
    ) -> TimeInterval {
        let limits = [
            configured,
            currentDuration > 0 ? currentDuration / 2 : configured,
            nextDuration > 0 ? nextDuration / 2 : configured,
        ]
        return max(limits.min() ?? 0, 0)
    }

    func beginCrossfade(
        predecessor: ResolvedPlaybackTrack,
        successor: ResolvedPlaybackTrack,
        duration: TimeInterval
    ) {
        let outgoingSlot = activeSlot
        let incomingSlot = outgoingSlot.other
        let outgoing = outgoingSlot.backend(in: self)
        let incoming = incomingSlot.backend(in: self)
        let acceptedGeneration = generation

        isTransitioning = true
        activeSlot = incomingSlot
        currentTrack = successor
        pendingPreparation = nil
        preparedSlot = nil
        preparedTrackID = nil
        preloadTask = nil

        incoming.play(fadeInDuration: .seconds(duration))
        transitionTask = Task { @MainActor [weak self] in
            await outgoing.setPresentationGain(
                0,
                duration: .seconds(duration)
            )
            guard let self,
                  !Task.isCancelled,
                  acceptedGeneration == generation,
                  activeSlot == incomingSlot
            else {
                return
            }
            outgoing.stop()
            isTransitioning = false
            transitionTask = nil
            if let pendingPreparation {
                schedulePreload(
                    pendingPreparation,
                    into: outgoingSlot,
                    generation: acceptedGeneration
                )
            }
        }
        onEvent?(
            .finished(
                trackID: predecessor.track.id,
                successorStarted: successor.track.id
            )
        )
    }

    func retireOverlapIfNeeded() {
        guard isTransitioning else {
            return
        }
        transitionTask?.cancel()
        transitionTask = nil
        inactiveBackend.stop()
        isTransitioning = false
        if let pendingPreparation {
            schedulePreload(
                pendingPreparation,
                into: activeSlot.other,
                generation: generation
            )
        }
    }

    func cancelPendingWork() {
        preloadTask?.cancel()
        preloadTask = nil
        transitionTask?.cancel()
        transitionTask = nil
    }
}
