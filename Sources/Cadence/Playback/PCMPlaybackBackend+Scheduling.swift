import AudioToolbox
import AVFAudio
import Foundation

enum PCMGainAutomation {
    static let silenceDecibels: Float = -96

    static func decibels(for scalar: Float) -> Float {
        let scalar = min(max(scalar, 0), 1)
        guard scalar > 0 else {
            return silenceDecibels
        }
        return max(20 * log10(scalar), silenceDecibels)
    }

    static func frameCount(
        duration: Duration,
        sampleRate: Double
    ) -> AUAudioFrameCount {
        let components = duration.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1e18
        return AUAudioFrameCount(
            min(max(seconds * sampleRate, 0), Double(UInt32.max))
        )
    }
}

struct PCMPlaybackStartTracker {
    let generation: Int
    private var firstSample: AVAudioFramePosition?
    private var observedRenderTime = false

    mutating func observe(
        engineRunning: Bool,
        nodePlaying: Bool,
        sampleTime: AVAudioFramePosition?,
        generation: Int
    ) -> PlaybackStartObservation? {
        guard generation == self.generation else {
            return .failed(.staleGeneration)
        }
        guard engineRunning else {
            return .failed(.engineStopped)
        }
        guard nodePlaying else {
            return .failed(.nodeStopped)
        }
        guard let sampleTime else {
            return nil
        }
        observedRenderTime = true
        if let firstSample, sampleTime > firstSample {
            return .started
        }
        firstSample = firstSample ?? sampleTime
        return nil
    }

    func timedOut() -> PlaybackStartObservation {
        .failed(
            observedRenderTime
                ? .renderDidNotAdvance
                : .renderTimeUnavailable
        )
    }
}

extension PCMPlaybackBackend {
    var currentPlayerSampleTime: AVAudioFramePosition? {
        guard
            let renderTime = playerNode.lastRenderTime,
            let playerTime = playerNode.playerTime(forNodeTime: renderTime)
        else {
            return nil
        }
        return playerTime.sampleTime
    }

    var currentPlaybackTime: TimeInterval {
        guard let currentItem,
              let playerSampleTime = currentPlayerSampleTime
        else {
            return lastKnownPlaybackTime
        }
        let elapsedFrames = max(
            playerSampleTime - currentStartSample,
            0
        )
        let playbackTime = logicalStartTime
            + Double(elapsedFrames) / currentItem.sampleRate
        lastKnownPlaybackTime = playbackTime
        return playbackTime
    }

    func timelineSample(
        hostUptime: TimeInterval
    ) -> PlaybackTimelineSample {
        PlaybackTimelineSample(
            mediaTime: currentPlaybackTime,
            hostUptime: hostUptime,
            rate: isPlaying ? 1 : 0
        )
    }

    func freezePlaybackTimeline(
        at time: TimeInterval,
        playerSampleTime: AVAudioFramePosition?
    ) {
        logicalStartTime = time
        lastKnownPlaybackTime = time
        if let playerSampleTime {
            currentStartSample = playerSampleTime
        }
    }

    func configureSchedule(
        current: ResolvedPlaybackTrack,
        next: ResolvedPlaybackTrack?,
        startTime: TimeInterval,
        autoplay: Bool
    ) throws {
        let wasRunning = engine.isRunning
        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        bassAnalyzer.invalidateScheduleBoundary()
        resetBassAnalysis()
        playerNode.stop()

        let currentItem = try scheduledItem(
            current,
            startTime: startTime
        )
        self.currentItem = currentItem
        preparedItem = nil
        currentSegmentTicket = makeSegmentTicket()
        preparedSegmentTicket = 0
        currentStartSample = 0
        currentScheduledEndSample = AVAudioFramePosition(
            currentItem.frameCount
        )
        logicalStartTime = startTime
        lastKnownPlaybackTime = startTime
        applyGain()
        schedule(
            currentItem,
            generation: generation,
            segmentTicket: currentSegmentTicket,
            startingSampleTime: 0
        )

        if let next {
            let nextItem = try scheduledItem(next, startTime: 0)
            if isGaplessCompatible(currentItem, nextItem) {
                preparedItem = nextItem
                preparedSegmentTicket = makeSegmentTicket()
                let successorStart = AVAudioFramePosition(
                    currentItem.frameCount
                )
                bassAnalyzer.scheduleSuccessorBoundary(
                    at: successorStart,
                    scheduleGeneration: UInt64(
                        truncatingIfNeeded: generation
                    ),
                    predecessorTicket: currentSegmentTicket
                )
                schedule(
                    nextItem,
                    generation: generation,
                    segmentTicket: preparedSegmentTicket,
                    startingSampleTime: successorStart
                )
            }
        }

        if autoplay, !wasRunning {
            try engine.start()
        }
        isPlaying = autoplay
        if autoplay {
            playerNode.play()
        }
        startProgressUpdates()
    }

    func scheduledItem(
        _ resolved: ResolvedPlaybackTrack,
        startTime: TimeInterval
    ) throws -> ScheduledPCMItem {
        let file = try AVAudioFile(forReading: resolved.mediaURL)
        guard file.length > 0 else {
            throw PlaybackFailure(
                trackID: resolved.track.id,
                message: "The PCM asset contains no schedulable audio frames."
            )
        }
        let lastSchedulableFrame = file.length - 1
        let startFrame = min(
            max(
                AVAudioFramePosition(
                    startTime * file.processingFormat.sampleRate
                ),
                0
            ),
            lastSchedulableFrame
        )
        let remaining = file.length - startFrame
        guard remaining <= AVAudioFramePosition(UInt32.max) else {
            throw PlaybackFailure(
                trackID: resolved.track.id,
                message: "The PCM asset is too large to schedule safely."
            )
        }
        return ScheduledPCMItem(
            resolved: resolved,
            file: file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remaining)
        )
    }

    func schedule(
        _ item: ScheduledPCMItem,
        generation: Int? = nil,
        segmentTicket: UInt64,
        startingSampleTime: AVAudioFramePosition? = nil
    ) {
        let trackID = item.resolved.track.id
        let generation = generation ?? scheduleGeneration
        let segmentEndSample = startingSampleTime.map {
            $0 + AVAudioFramePosition(item.frameCount)
        }
        let bassAnalyzer = bassAnalyzer
        playerNode.scheduleSegment(
            item.file,
            startingFrame: item.startingFrame,
            frameCount: item.frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            bassAnalyzer.resetAtSuccessorBoundary(
                segmentEndSample,
                scheduleGeneration: UInt64(
                    truncatingIfNeeded: generation
                ),
                predecessorTicket: segmentTicket
            )
            Task { @MainActor [weak self] in
                self?.handleFinished(
                    trackID: trackID,
                    generation: generation,
                    segmentTicket: segmentTicket
                )
            }
        }
    }

    func isGaplessCompatible(
        _ current: ScheduledPCMItem,
        _ next: ScheduledPCMItem
    ) -> Bool {
        current.sampleRate == next.sampleRate
            && current.file.processingFormat.channelCount
            == next.file.processingFormat.channelCount
    }

    func handleFinished(
        trackID: UUID,
        generation: Int? = nil,
        segmentTicket: UInt64? = nil
    ) {
        let acceptedGeneration = generation ?? scheduleGeneration
        guard acceptedGeneration == scheduleGeneration else {
            return
        }
        guard currentItem?.resolved.track.id == trackID else {
            return
        }
        let acceptedTicket = segmentTicket ?? currentSegmentTicket
        guard acceptedTicket != 0,
              acceptedTicket == currentSegmentTicket else {
            return
        }
        if let preparedItem {
            let successorStartSample = currentScheduledEndSample
            bassAnalyzer.resetAtSuccessorBoundary(
                successorStartSample,
                scheduleGeneration: UInt64(
                    truncatingIfNeeded: acceptedGeneration
                ),
                predecessorTicket: acceptedTicket
            )
            resetBassAnalysis()
            currentItem = preparedItem
            self.preparedItem = nil
            currentSegmentTicket = preparedSegmentTicket
            preparedSegmentTicket = 0
            currentStartSample = successorStartSample
            currentScheduledEndSample = successorStartSample
                + AVAudioFramePosition(preparedItem.frameCount)
            logicalStartTime = 0
            lastKnownPlaybackTime = 0
            applyGain()
            onEvent?(
                .finished(
                    trackID: trackID,
                    successorStarted: preparedItem.resolved.track.id
                )
            )
        } else {
            onEvent?(
                .finished(
                    trackID: trackID,
                    successorStarted: nil
                )
            )
        }
    }

    func makeSegmentTicket() -> UInt64 {
        precondition(
            nextSegmentTicket < UInt64.max,
            "PCM schedule ticket space exhausted."
        )
        nextSegmentTicket += 1
        return nextSegmentTicket
    }

    func applyGain() {
        applyGain(duration: .milliseconds(12))
    }

    func applyGain(
        duration: Duration
    ) {
        playerNode.volume = 1
        let targetScalar = min(
            max(userVolume * normalizationGain * presentationGain, 0),
            1
        )
        engine.mainMixerNode.outputVolume = 1
        let targetDecibels = PCMGainAutomation.decibels(
            for: targetScalar
        )
        let frameCount = PCMGainAutomation.frameCount(
            duration: duration,
            sampleRate: max(engine.outputNode.outputFormat(forBus: 0).sampleRate, 1)
        )
        guard engine.isRunning, frameCount > 0,
              let parameter = gainUnit.auAudioUnit.parameterTree?
              .allParameters.first(where: {
                  $0.identifier.localizedCaseInsensitiveContains("gain")
              })
        else {
            gainUnit.globalGain = targetDecibels
            return
        }
        gainUnit.auAudioUnit.scheduleParameterBlock(
            AUEventSampleTimeImmediate,
            frameCount,
            parameter.address,
            targetDecibels
        )
    }

    func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else {
                    return
                }
                onEvent?(
                    .timeline(
                        timelineSample(
                            hostUptime: ProcessInfo.processInfo.systemUptime
                        )
                    )
                )
            }
        }
    }

    func emitFailure(_ error: Error) {
        onEvent?(
            .failed(
                PlaybackFailure(
                    trackID: currentItem?.resolved.track.id,
                    message: error.localizedDescription
                )
            )
        )
    }
}
