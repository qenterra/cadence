import AVFAudio
import Foundation

@MainActor
final class PCMPlaybackBackend: PlaybackBackend {
    let kind = PlaybackBackendKind.pcm
    var onEvent: ((PlaybackBackendEvent) -> Void)?

    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    let gainUnit = AVAudioUnitEQ(numberOfBands: 0)
    let bassMeter: PCMBassLevelMeter
    let bassAnalyzer: PCMBassAnalyzer
    var currentItem: ScheduledPCMItem?
    var preparedItem: ScheduledPCMItem?
    var progressTask: Task<Void, Never>?
    var currentStartSample: AVAudioFramePosition = 0
    var currentScheduledEndSample: AVAudioFramePosition = 0
    var logicalStartTime: TimeInterval = 0
    var lastKnownPlaybackTime: TimeInterval = 0
    var isPlaying = false
    var userVolume: Float = 0.72
    var normalizationGain: Float = 1
    var scheduleGeneration = 0
    var nextSegmentTicket: UInt64 = 0
    var currentSegmentTicket: UInt64 = 0
    var preparedSegmentTicket: UInt64 = 0
    var presentationGain: Float = 1
    var gainRampGeneration = 0

    var bassLevelProvider: (any PlaybackBassLevelProviding)? {
        bassMeter
    }

    init() {
        let bassMeter = PCMBassLevelMeter()
        self.bassMeter = bassMeter
        bassAnalyzer = PCMBassAnalyzer(meter: bassMeter)
        engine.attach(playerNode)
        engine.attach(gainUnit)
        engine.connect(
            playerNode,
            to: gainUnit,
            format: nil
        )
        engine.connect(
            gainUnit,
            to: engine.mainMixerNode,
            format: nil
        )
        playerNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: nil,
            block: makePCMBassTap(analyzer: bassAnalyzer)
        )
        engine.mainMixerNode.outputVolume = 1
    }

    func load(
        _ request: PlaybackBackendLoadRequest
    ) async throws {
        if currentItem != nil, isPlaying {
            await setPresentationGain(0, duration: .milliseconds(36))
        }
        gainRampGeneration &+= 1
        userVolume = request.volume
        normalizationGain = request.normalizationGain
        presentationGain = request.autoplay ? 0 : 1
        try configureSchedule(
            current: request.current,
            next: request.next,
            startTime: request.startTime,
            autoplay: request.autoplay
        )
        if request.autoplay {
            await setPresentationGain(1, duration: .milliseconds(90))
        }
        onEvent?(.duration(request.current.track.duration))
    }

    func prepareNext(
        _ track: ResolvedPlaybackTrack?
    ) async throws {
        guard preparedItem?.resolved.track.id != track?.track.id else {
            return
        }
        guard let currentItem else {
            return
        }
        if preparedItem == nil, let track {
            let nextItem = try scheduledItem(track, startTime: 0)
            guard isGaplessCompatible(currentItem, nextItem) else {
                return
            }
            preparedItem = nextItem
            preparedSegmentTicket = makeSegmentTicket()
            let successorStart = currentScheduledEndSample
            bassAnalyzer.scheduleSuccessorBoundary(
                at: successorStart,
                scheduleGeneration: UInt64(
                    truncatingIfNeeded: scheduleGeneration
                ),
                predecessorTicket: currentSegmentTicket
            )
            schedule(
                nextItem,
                segmentTicket: preparedSegmentTicket,
                startingSampleTime: successorStart
            )
            return
        }
        try configureSchedule(
            current: currentItem.resolved,
            next: track,
            startTime: currentPlaybackTime,
            autoplay: isPlaying
        )
    }

    func verifyStart(
        timeout: Duration
    ) async -> PlaybackStartObservation {
        let generation = scheduleGeneration
        var tracker = PCMPlaybackStartTracker(generation: generation)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if let observation = tracker.observe(
                engineRunning: engine.isRunning,
                nodePlaying: playerNode.isPlaying,
                sampleTime: currentPlayerSampleTime,
                generation: scheduleGeneration
            ) {
                return observation
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return tracker.timedOut()
    }

    func play() {
        play(fadeInDuration: .milliseconds(80))
    }

    func play(fadeInDuration: Duration) {
        guard currentItem != nil else {
            return
        }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                emitFailure(error)
                return
            }
        }
        gainRampGeneration &+= 1
        presentationGain = 0
        applyGain(duration: .zero)
        playerNode.play()
        isPlaying = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await setPresentationGain(1, duration: fadeInDuration)
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
            let pausedTime = currentPlaybackTime
            let pausedSampleTime = currentPlayerSampleTime
            playerNode.pause()
            isPlaying = false
            freezePlaybackTimeline(
                at: pausedTime,
                playerSampleTime: pausedSampleTime
            )
            onEvent?(
                .timeline(
                    timelineSample(
                        hostUptime: ProcessInfo.processInfo.systemUptime
                    )
                )
            )
        }
    }

    func seek(to time: TimeInterval) async throws {
        guard let current = currentItem?.resolved else {
            return
        }
        let resumesPlayback = isPlaying
        if resumesPlayback {
            await setPresentationGain(0, duration: .milliseconds(28))
        }
        try configureSchedule(
            current: current,
            next: preparedItem?.resolved,
            startTime: time,
            autoplay: isPlaying
        )
        if resumesPlayback {
            await setPresentationGain(1, duration: .milliseconds(42))
        }
        onEvent?(
            .timeline(
                timelineSample(
                    hostUptime: ProcessInfo.processInfo.systemUptime
                )
            )
        )
    }

    func setVolume(_ volume: Float) {
        userVolume = min(max(volume, 0), 1)
        applyGain()
    }

    func setNormalizationGain(_ gain: Float) {
        normalizationGain = min(max(gain, 0), 4)
        applyGain()
    }

    func setPresentationGain(
        _ gain: Float,
        duration: Duration
    ) async {
        gainRampGeneration &+= 1
        let generation = gainRampGeneration
        await rampPresentationGain(
            to: gain,
            duration: duration,
            generation: generation
        )
    }

    func stop() {
        progressTask?.cancel()
        progressTask = nil
        scheduleGeneration &+= 1
        gainRampGeneration &+= 1
        playerNode.stop()
        engine.pause()
        currentItem = nil
        preparedItem = nil
        currentSegmentTicket = 0
        preparedSegmentTicket = 0
        currentStartSample = 0
        currentScheduledEndSample = 0
        logicalStartTime = 0
        lastKnownPlaybackTime = 0
        isPlaying = false
        presentationGain = 1
        bassAnalyzer.invalidateScheduleBoundary()
        resetBassAnalysis()
    }

    func resetBassAnalysis() {
        bassAnalyzer.resetAnalysisState()
    }

    private func rampPresentationGain(
        to target: Float,
        duration: Duration,
        generation: Int
    ) async {
        let target = min(max(target, 0), 1)
        guard generation == gainRampGeneration else {
            return
        }
        presentationGain = target
        applyGain(duration: duration)
        if duration > .zero {
            try? await Task.sleep(for: duration)
        }
    }
}

struct ScheduledPCMItem {
    let resolved: ResolvedPlaybackTrack
    let file: AVAudioFile
    let startingFrame: AVAudioFramePosition
    let frameCount: AVAudioFrameCount

    var sampleRate: Double {
        file.processingFormat.sampleRate
    }
}
