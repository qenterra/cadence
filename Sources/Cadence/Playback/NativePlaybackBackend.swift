import AVFoundation
import Foundation

@MainActor
final class NativePlaybackBackend: NSObject, PlaybackBackend {
    let kind = PlaybackBackendKind.native
    var onEvent: ((PlaybackBackendEvent) -> Void)?

    private let player = AVPlayer()
    private var periodicTimeObserver: Any?
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var currentTrackID: UUID?
    private var expectedDuration: TimeInterval = 0
    private var userVolume: Float = 0.72
    private var presentationGain: Float = 1
    private var gainRampGeneration = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidFinish(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    func load(
        _ request: PlaybackBackendLoadRequest
    ) async throws {
        let asset = AVURLAsset(url: request.current.mediaURL)
        guard try await asset.load(.isPlayable) else {
            throw PlaybackFailure(
                trackID: request.current.track.id,
                message: "The system player cannot decode this audio file."
            )
        }

        let item = AVPlayerItem(asset: asset)
        currentTrackID = request.current.track.id
        expectedDuration = request.current.track.duration
        userVolume = request.volume
        presentationGain = request.autoplay ? 0 : 1
        stopTimelineObservation()
        player.replaceCurrentItem(with: item)
        startTimelineObservation()
        applyVolume()

        if request.startTime > 0 {
            await seekPlayer(to: request.startTime)
        }
        if request.autoplay {
            player.play()
            await setPresentationGain(1, duration: .milliseconds(90))
        } else {
            player.pause()
        }

        onEvent?(.duration(expectedDuration))
        emitTimelineSample()
    }

    func prepareNext(_: ResolvedPlaybackTrack?) async throws {}

    func verifyStart(
        timeout: Duration
    ) async -> PlaybackStartObservation {
        let expectedTrackID = currentTrackID
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            guard expectedTrackID == currentTrackID else {
                return .failed(.staleGeneration)
            }
            if player.currentItem?.status == .readyToPlay,
               player.timeControlStatus == .playing {
                return .started
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return .failed(.renderDidNotAdvance)
    }

    func play() {
        gainRampGeneration &+= 1
        presentationGain = 0
        applyVolume()
        player.play()
        Task { @MainActor [weak self] in
            await self?.setPresentationGain(1, duration: .milliseconds(80))
        }
    }

    func pause() {
        gainRampGeneration &+= 1
        let generation = gainRampGeneration
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await rampPresentationGain(
                to: 0,
                duration: .milliseconds(70),
                generation: generation
            )
            guard generation == gainRampGeneration else {
                return
            }
            player.pause()
        }
    }

    func seek(to time: TimeInterval) async throws {
        await seekPlayer(to: time)
        emitTimelineSample(mediaTime: time)
    }

    func setVolume(_ volume: Float) {
        userVolume = min(max(volume, 0), 1)
        applyVolume()
    }

    func setPresentationGain(
        _ gain: Float,
        duration: Duration
    ) async {
        gainRampGeneration &+= 1
        await rampPresentationGain(
            to: gain,
            duration: duration,
            generation: gainRampGeneration
        )
    }

    func stop() {
        stopTimelineObservation()
        gainRampGeneration &+= 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentTrackID = nil
        expectedDuration = 0
        presentationGain = 1
    }

    @objc
    private func playerItemDidFinish(
        _ notification: Notification
    ) {
        guard
            notification.object as? AVPlayerItem === player.currentItem,
            let currentTrackID
        else {
            return
        }
        onEvent?(
            .finished(
                trackID: currentTrackID,
                successorStarted: nil
            )
        )
    }

    private func seekPlayer(
        to time: TimeInterval
    ) async {
        await withCheckedContinuation { continuation in
            player.seek(
                to: CMTime(seconds: time, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { _ in
                continuation.resume()
            }
        }
    }

    static func timelineRate(
        playerRate: Float,
        status: AVPlayer.TimeControlStatus
    ) -> Double {
        guard status == .playing else {
            return 0
        }
        return max(Double(playerRate), 0)
    }

    private func startTimelineObservation() {
        stopTimelineObservation()
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.emitTimelineSample(mediaTime: time.seconds)
            }
        }
        timeControlStatusObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.emitTimelineSample()
            }
        }
    }

    private func stopTimelineObservation() {
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil
    }

    private func emitTimelineSample(
        mediaTime: TimeInterval? = nil
    ) {
        guard player.currentItem != nil else {
            return
        }
        let seconds = mediaTime ?? player.currentTime().seconds
        guard seconds.isFinite else {
            return
        }
        onEvent?(
            .timeline(
                PlaybackTimelineSample(
                    mediaTime: seconds,
                    hostUptime: ProcessInfo.processInfo.systemUptime,
                    rate: Self.timelineRate(
                        playerRate: player.rate,
                        status: player.timeControlStatus
                    )
                )
            )
        )
        if let error = player.currentItem?.error {
            onEvent?(
                .failed(
                    PlaybackFailure(
                        trackID: currentTrackID,
                        message: error.localizedDescription
                    )
                )
            )
        }
    }

    private func applyVolume() {
        player.volume = userVolume * presentationGain
    }

    private func rampPresentationGain(
        to target: Float,
        duration: Duration,
        generation: Int
    ) async {
        let target = min(max(target, 0), 1)
        let start = presentationGain
        let steps = 10
        for step in 1 ... steps {
            guard generation == gainRampGeneration else {
                return
            }
            presentationGain = start
                + (target - start) * Float(step) / Float(steps)
            applyVolume()
            if step < steps {
                try? await Task.sleep(for: duration / steps)
            }
        }
    }
}
