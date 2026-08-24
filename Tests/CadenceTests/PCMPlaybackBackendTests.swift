import AVFAudio
@testable import Cadence
import Foundation
import Testing

@MainActor
struct PCMPlaybackBackendTests {
    @Test("Compatible lossless files are scheduled without an engine restart")
    func gaplessSchedule() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let first = try makeWave(
            at: directory.appending(path: "first.wav"),
            id: UUID(),
            title: "First",
            phaseOffset: 0
        )
        let second = try makeWave(
            at: directory.appending(path: "second.wav"),
            id: UUID(),
            title: "Second",
            phaseOffset: 1024
        )
        let backend = PCMPlaybackBackend()
        var transition: (UUID, UUID?)?
        backend.onEvent = { event in
            if case let .finished(trackID, successorStarted) = event {
                transition = (trackID, successorStarted)
            }
        }

        try await backend.load(
            PlaybackBackendLoadRequest(
                current: first,
                next: second,
                startTime: 0,
                autoplay: false,
                volume: 0.8
            )
        )

        let firstFrameCount = try #require(backend.currentItem?.frameCount)
        #expect(backend.preparedItem?.resolved.track.id == second.track.id)
        #expect(!backend.engine.isRunning)

        backend.bassMeter.store(0.8)
        backend.handleFinished(trackID: first.track.id)

        #expect(backend.currentItem?.resolved.track.id == second.track.id)
        #expect(backend.bassMeter.currentBassLevel() == 0)
        #expect(
            backend.currentStartSample
                == AVAudioFramePosition(firstFrameCount)
        )
        #expect(transition?.0 == first.track.id)
        #expect(transition?.1 == second.track.id)
        backend.stop()
    }

    @Test("An incompatible sample rate is not advertised as gapless")
    func incompatibleFormat() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let first = try makeWave(
            at: directory.appending(path: "first.wav"),
            id: UUID(),
            title: "First",
            sampleRate: 44100
        )
        let second = try makeWave(
            at: directory.appending(path: "second.wav"),
            id: UUID(),
            title: "Second",
            sampleRate: 48000
        )
        let backend = PCMPlaybackBackend()

        try await backend.load(
            PlaybackBackendLoadRequest(
                current: first,
                next: second,
                startTime: 0,
                autoplay: false,
                volume: 1
            )
        )

        #expect(backend.preparedItem == nil)
        backend.stop()
    }

    @Test("A stale completion after seek cannot finish the current track")
    func staleCompletionAfterSeek() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let track = try makeWave(
            at: directory.appending(path: "seek.wav"),
            id: UUID(),
            title: "Seek"
        )
        let backend = PCMPlaybackBackend()
        var finishedTrackIDs: [UUID] = []
        backend.onEvent = { event in
            if case let .finished(trackID, _) = event {
                finishedTrackIDs.append(trackID)
            }
        }

        try await backend.load(
            PlaybackBackendLoadRequest(
                current: track,
                next: nil,
                startTime: 0,
                autoplay: false,
                volume: 0.8
            )
        )
        let staleGeneration = backend.scheduleGeneration

        try await backend.seek(to: track.track.duration / 2)
        backend.handleFinished(
            trackID: track.track.id,
            generation: staleGeneration
        )

        #expect(finishedTrackIDs.isEmpty)
        #expect(backend.currentItem?.resolved.track.id == track.track.id)
        #expect(backend.logicalStartTime == track.track.duration / 2)
        backend.stop()
    }

    @Test("Load, seek, and stop clear PCM bass state")
    func bassResetLifecycle() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let track = try makeWave(
            at: directory.appending(path: "reset.wav"),
            id: UUID(),
            title: "Reset"
        )
        let backend = PCMPlaybackBackend()

        backend.bassMeter.store(0.9)
        try await backend.load(
            PlaybackBackendLoadRequest(
                current: track,
                next: nil,
                startTime: 0,
                autoplay: false,
                volume: 1
            )
        )
        #expect(backend.bassMeter.currentBassLevel() == 0)

        backend.bassMeter.store(0.7)
        try await backend.seek(to: track.track.duration / 2)
        #expect(backend.bassMeter.currentBassLevel() == 0)

        backend.bassMeter.store(0.5)
        backend.stop()
        #expect(backend.bassMeter.currentBassLevel() == 0)
    }

    @Test("A straddled gapless tap buffer starts the successor fresh")
    func exactGaplessBassBoundary() throws {
        let sampleRate = 48000.0
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: false
            )
        )
        let combined = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)
        )
        combined.frameLength = 1024
        let combinedChannels = try #require(combined.floatChannelData)
        for frame in 0 ..< 1024 {
            let frequency = frame < 512 ? 80.0 : 80.0
            let amplitude = frame < 512 ? 0.9 : 0.02
            let sample = Float(
                amplitude * sin(Double(frame) * 2 * .pi * frequency / sampleRate)
            )
            combinedChannels[0][frame] = sample
            combinedChannels[1][frame] = sample
        }

        let successorOnly = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)
        )
        successorOnly.frameLength = 512
        let successorChannels = try #require(successorOnly.floatChannelData)
        for frame in 0 ..< 512 {
            successorChannels[0][frame] = combinedChannels[0][frame + 512]
            successorChannels[1][frame] = combinedChannels[1][frame + 512]
        }

        let boundaryMeter = PCMBassLevelMeter()
        let boundaryAnalyzer = PCMBassAnalyzer(meter: boundaryMeter)
        boundaryAnalyzer.scheduleSuccessorBoundary(
            at: 512,
            scheduleGeneration: 1,
            predecessorTicket: 1
        )
        boundaryAnalyzer.process(
            combined,
            at: AVAudioTime(sampleTime: 0, atRate: sampleRate)
        )

        let freshMeter = PCMBassLevelMeter()
        let freshAnalyzer = PCMBassAnalyzer(meter: freshMeter)
        freshAnalyzer.process(
            successorOnly,
            at: AVAudioTime(sampleTime: 512, atRate: sampleRate)
        )

        #expect(
            abs(
                boundaryMeter.currentBassLevel()
                    - freshMeter.currentBassLevel()
            ) < 0.000_001
        )
    }
}

extension PCMPlaybackBackendTests {
    @Test("Late gapless preparation keeps the scheduled end after pause")
    func lateGaplessPreparationAfterPause() async throws {
        try await assertLateGaplessBoundary(
            seekTime: nil,
            frozenPlayerSample: 48000
        )
    }

    @Test("Late gapless preparation keeps a seek-origin scheduled end")
    func lateGaplessPreparationAfterSeek() async throws {
        try await assertLateGaplessBoundary(
            seekTime: 2,
            frozenPlayerSample: 48000
        )
    }

    @Test("Accepted-load bass activation preserves the real PCM boundary")
    func coordinatorLoadActivationPreservesGaplessBoundary() async throws {
        try await assertCoordinatorLifecyclePreservesGaplessBoundary(
            .acceptedLoadActivation
        )
    }

    @Test("Resume bass activation preserves the real PCM boundary")
    func coordinatorResumeActivationPreservesGaplessBoundary() async throws {
        try await assertCoordinatorLifecyclePreservesGaplessBoundary(
            .resumeActivation
        )
    }

    @Test("Post-seek bass activation preserves the rebuilt PCM boundary")
    func coordinatorSeekActivationPreservesGaplessBoundary() async throws {
        try await assertCoordinatorLifecyclePreservesGaplessBoundary(.seek)
    }

    @Test("A same-backend route refresh preserves the real PCM boundary")
    func coordinatorSameBackendRoutePreservesGaplessBoundary() async throws {
        try await assertCoordinatorLifecyclePreservesGaplessBoundary(
            .sameBackendRoute
        )
    }

    @Test("A coordinator seek rejects the prior equal-sample completion")
    func coordinatorSeekRearmRejectsStaleCompletion() async throws {
        try await assertCoordinatorLifecyclePreservesGaplessBoundary(
            .equalSampleSeekWithStaleCompletion
        )
    }

    @Test("A stale equal-sample completion cannot consume a rearmed boundary")
    func staleEqualSampleCompletionCannotClearReplacementBoundary() throws {
        let meter = PCMBassLevelMeter()
        let analyzer = PCMBassAnalyzer(meter: meter)

        analyzer.scheduleSuccessorBoundary(
            at: 512,
            scheduleGeneration: 1,
            predecessorTicket: 41
        )
        analyzer.scheduleSuccessorBoundary(
            at: 512,
            scheduleGeneration: 2,
            predecessorTicket: 42
        )
        analyzer.resetAtSuccessorBoundary(
            512,
            scheduleGeneration: 1,
            predecessorTicket: 41
        )

        try assertSuccessorStartsFresh(analyzer: analyzer, meter: meter)
    }

    @Test("Successor adoption gives the following transition new authority")
    func threeTrackBoundaryAuthorityCannotBeClearedByPriorCompletion() throws {
        let meter = PCMBassLevelMeter()
        let analyzer = PCMBassAnalyzer(meter: meter)

        analyzer.scheduleSuccessorBoundary(
            at: 512,
            scheduleGeneration: 7,
            predecessorTicket: 51
        )
        analyzer.resetAtSuccessorBoundary(
            512,
            scheduleGeneration: 7,
            predecessorTicket: 51
        )
        analyzer.scheduleSuccessorBoundary(
            at: 512,
            scheduleGeneration: 7,
            predecessorTicket: 52
        )
        analyzer.resetAtSuccessorBoundary(
            512,
            scheduleGeneration: 7,
            predecessorTicket: 51
        )

        try assertSuccessorStartsFresh(analyzer: analyzer, meter: meter)
    }

    @Test("The installed PCM tap analyzes a temporary 80 Hz WAV")
    func installedTapTemporaryWave() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let track = try makeWave(
            at: directory.appending(path: "bass.wav"),
            id: UUID(),
            title: "Bass",
            frameCount: 48000,
            frequency: 80,
            amplitude: 0.5
        )
        let backend = PCMPlaybackBackend()
        defer { backend.stop() }

        try await backend.load(
            PlaybackBackendLoadRequest(
                current: track,
                next: nil,
                startTime: 0,
                autoplay: true,
                volume: 0
            )
        )
        var observedLevel: Float = 0
        for _ in 0 ..< 50 where observedLevel == 0 {
            try await Task.sleep(for: .milliseconds(20))
            observedLevel = backend.bassMeter.currentBassLevel()
        }

        #expect(backend.engine.isRunning)
        #expect(observedLevel > 0)
    }
}

extension PCMPlaybackBackendTests {
    @Test("Pausing freezes the PCM timeline at the rendered position")
    func pauseFreezesRenderedPosition() {
        let backend = PCMPlaybackBackend()
        backend.logicalStartTime = 80
        backend.lastKnownPlaybackTime = 95
        backend.currentStartSample = 100

        #expect(backend.currentPlaybackTime == 95)

        backend.freezePlaybackTimeline(
            at: 96,
            playerSampleTime: 768_100
        )

        #expect(backend.logicalStartTime == 96)
        #expect(backend.lastKnownPlaybackTime == 96)
        #expect(backend.currentStartSample == 768_100)
        backend.stop()
    }

    @Test("User volume is applied through the rampable gain unit")
    func outputVolume() {
        let backend = PCMPlaybackBackend()

        backend.setVolume(0.25)

        #expect(backend.userVolume == 0.25)
        #expect(backend.engine.mainMixerNode.outputVolume == 1)
        #expect(abs(backend.gainUnit.globalGain - -12.0412) < 0.01)
        backend.stop()
    }

    @Test("PCM timeline samples expose rendered time and transport rate")
    func timelineSamples() {
        let backend = PCMPlaybackBackend()
        backend.lastKnownPlaybackTime = 95
        backend.isPlaying = true

        let advancing = backend.timelineSample(hostUptime: 12)

        #expect(advancing.mediaTime == 95)
        #expect(advancing.hostUptime == 12)
        #expect(advancing.rate == 1)

        backend.isPlaying = false
        #expect(backend.timelineSample(hostUptime: 13).rate == 0)
        backend.stop()
    }

    @Test("PCM start tracking requires sample progression")
    func startTrackingRequiresProgression() {
        var tracker = PCMPlaybackStartTracker(generation: 7)

        #expect(
            tracker.observe(
                engineRunning: true,
                nodePlaying: true,
                sampleTime: 120,
                generation: 7
            ) == nil
        )
        #expect(
            tracker.observe(
                engineRunning: true,
                nodePlaying: true,
                sampleTime: 120,
                generation: 7
            ) == nil
        )
        #expect(tracker.timedOut() == .failed(.renderDidNotAdvance))

        #expect(
            tracker.observe(
                engineRunning: true,
                nodePlaying: true,
                sampleTime: 256,
                generation: 7
            ) == .started
        )
    }

    @Test("PCM start tracking distinguishes unavailable and stale renders")
    func startTrackingFailures() {
        var missingRender = PCMPlaybackStartTracker(generation: 4)
        #expect(
            missingRender.observe(
                engineRunning: true,
                nodePlaying: true,
                sampleTime: nil,
                generation: 4
            ) == nil
        )
        #expect(
            missingRender.timedOut()
                == .failed(.renderTimeUnavailable)
        )

        var stale = PCMPlaybackStartTracker(generation: 4)
        #expect(
            stale.observe(
                engineRunning: true,
                nodePlaying: true,
                sampleTime: 1,
                generation: 5
            ) == .failed(.staleGeneration)
        )
    }

    private func makeWave(
        at url: URL,
        id: UUID,
        title: String,
        sampleRate: Double = 48000,
        phaseOffset: Int = 0,
        frameCount: AVAudioFrameCount = 1024,
        frequency: Double = 440,
        amplitude: Float = 1
    ) throws -> ResolvedPlaybackTrack {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: false
            )
        )
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            )
        )
        buffer.frameLength = frameCount
        let channels = try #require(buffer.floatChannelData)
        for frame in 0 ..< Int(frameCount) {
            let sample = Float(
                Double(amplitude)
                    * sin(
                        Double(frame + phaseOffset) * 2 * .pi * frequency
                            / sampleRate
                    )
            )
            channels[0][frame] = sample
            channels[1][frame] = sample
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings
        )
        try file.write(from: buffer)

        let base = playbackTestTrack(
            id: id,
            title: title,
            codec: "LPCM",
            container: "wav",
            duration: Double(frameCount) / sampleRate,
            sampleRate: sampleRate
        )
        return ResolvedPlaybackTrack(
            track: base.track,
            mediaURL: url
        )
    }

    private func assertLateGaplessBoundary(
        seekTime: TimeInterval?,
        frozenPlayerSample: AVAudioFramePosition
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let current = try makeWave(
            at: directory.appending(path: "current.wav"),
            id: UUID(),
            title: "Current",
            frameCount: 480_000,
            frequency: 80,
            amplitude: 0.9
        )
        let successor = try makeWave(
            at: directory.appending(path: "successor.wav"),
            id: UUID(),
            title: "Successor",
            frameCount: 4800,
            frequency: 80,
            amplitude: 0.02
        )
        let backend = PCMPlaybackBackend()
        defer { backend.stop() }
        try await backend.load(
            PlaybackBackendLoadRequest(
                current: current,
                next: nil,
                startTime: 0,
                autoplay: false,
                volume: 0
            )
        )
        if let seekTime {
            try await backend.seek(to: seekTime)
        }
        let actualScheduledEnd = try AVAudioFramePosition(
            #require(backend.currentItem?.frameCount)
        )
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48000,
                channels: 2,
                interleaved: false
            )
        )
        let loud = try stereoSineBuffer(
            format: format,
            amplitude: 0.9
        )
        let quiet = try stereoSineBuffer(
            format: format,
            amplitude: 0.02
        )
        backend.bassAnalyzer.process(
            loud,
            at: AVAudioTime(sampleTime: 0, atRate: format.sampleRate)
        )
        backend.freezePlaybackTimeline(
            at: (seekTime ?? 0) + 1,
            playerSampleTime: frozenPlayerSample
        )

        try await backend.prepareNext(successor)
        backend.bassAnalyzer.process(
            quiet,
            at: AVAudioTime(
                sampleTime: actualScheduledEnd,
                atRate: format.sampleRate
            )
        )

        let freshMeter = PCMBassLevelMeter()
        let freshAnalyzer = PCMBassAnalyzer(meter: freshMeter)
        freshAnalyzer.process(
            quiet,
            at: AVAudioTime(
                sampleTime: actualScheduledEnd,
                atRate: format.sampleRate
            )
        )
        #expect(
            abs(
                backend.bassMeter.currentBassLevel()
                    - freshMeter.currentBassLevel()
            ) < 0.000_001
        )
    }

    @MainActor
    private func assertCoordinatorLifecyclePreservesGaplessBoundary(
        _ lifecycle: CoordinatorBassLifecycle
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let current = try makeWave(
            at: directory.appending(path: "coordinator-current.wav"),
            id: UUID(),
            title: "Coordinator Current",
            frameCount: 8192,
            frequency: 80,
            amplitude: 0.9
        )
        let successor = try makeWave(
            at: directory.appending(path: "coordinator-successor.wav"),
            id: UUID(),
            title: "Coordinator Successor",
            frameCount: 4096,
            frequency: 80,
            amplitude: 0.02
        )
        let builtIn = AudioRouteSnapshot(
            name: "Built-in Output",
            transport: .builtIn
        )
        let routeProvider = PlaybackTestAudioRouteProvider(route: builtIn)
        let backend = PCMPlaybackBackend()
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: [current, successor]),
            backends: [backend],
            audioRouteProvider: routeProvider
        )
        defer { coordinator.shutdown() }
        coordinator.activateSystemMediaSession()
        let trackIDs = [current.track.id, successor.track.id]
        coordinator.canonicalOrder = trackIDs
        coordinator.state.queue = PlaybackQueueState(
            source: .adHoc,
            orderedTrackIDs: trackIDs,
            startingAt: current.track.id
        )
        #expect(
            await coordinator.loadCurrent(startTime: 0, autoplay: false)
        )
        _ = try #require(backend.preparedItem)
        let staleBoundary = backend.currentScheduledEndSample
        let staleScheduleGeneration = UInt64(
            truncatingIfNeeded: backend.scheduleGeneration
        )
        let staleSegmentTicket = backend.currentSegmentTicket

        switch lifecycle {
        case .acceptedLoadActivation:
            coordinator.state.transport = .playing
            coordinator.activateBassSourceForCurrentTrack()
        case .resumeActivation:
            coordinator.invalidateBassState()
            coordinator.state.transport = .playing
            coordinator.activateBassSourceForCurrentTrack()
        case .seek:
            coordinator.state.transport = .playing
            await coordinator.seek(to: 0.01)
        case .sameBackendRoute:
            coordinator.state.transport = .playing
            routeProvider.emit(
                AudioRouteSnapshot(name: "Headphones", transport: .wired)
            )
            await coordinator.waitForAudioRouteTransitions()
        case .equalSampleSeekWithStaleCompletion:
            coordinator.state.transport = .playing
            await coordinator.seek(to: 0)
            backend.bassAnalyzer.resetAtSuccessorBoundary(
                staleBoundary,
                scheduleGeneration: staleScheduleGeneration,
                predecessorTicket: staleSegmentTicket
            )
        }

        _ = try #require(backend.preparedItem)
        try assertSuccessorStartsFresh(
            analyzer: backend.bassAnalyzer,
            meter: backend.bassMeter,
            boundary: backend.currentScheduledEndSample
        )
    }

    private func assertSuccessorStartsFresh(
        analyzer: PCMBassAnalyzer,
        meter: PCMBassLevelMeter,
        boundary: AVAudioFramePosition = 512
    ) throws {
        let sampleRate = 48000.0
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: false
            )
        )
        let combined = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)
        )
        combined.frameLength = 1024
        let combinedChannels = try #require(combined.floatChannelData)
        for frame in 0 ..< 1024 {
            let amplitude = frame < 512 ? 0.9 : 0.02
            let sample = Float(
                amplitude * sin(Double(frame) * 2 * .pi * 80 / sampleRate)
            )
            combinedChannels[0][frame] = sample
            combinedChannels[1][frame] = sample
        }
        let successorOnly = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)
        )
        successorOnly.frameLength = 512
        let successorChannels = try #require(successorOnly.floatChannelData)
        for frame in 0 ..< 512 {
            successorChannels[0][frame] = combinedChannels[0][frame + 512]
            successorChannels[1][frame] = combinedChannels[1][frame + 512]
        }

        analyzer.process(
            combined,
            at: AVAudioTime(
                sampleTime: boundary - 512,
                atRate: sampleRate
            )
        )
        let freshMeter = PCMBassLevelMeter()
        let freshAnalyzer = PCMBassAnalyzer(meter: freshMeter)
        freshAnalyzer.process(
            successorOnly,
            at: AVAudioTime(sampleTime: boundary, atRate: sampleRate)
        )

        #expect(
            abs(meter.currentBassLevel() - freshMeter.currentBassLevel())
                < 0.000_001
        )
    }

    private func stereoSineBuffer(
        format: AVAudioFormat,
        amplitude: Float,
        frameCount: AVAudioFrameCount = 1024
    ) throws -> AVAudioPCMBuffer {
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            )
        )
        buffer.frameLength = frameCount
        let channels = try #require(buffer.floatChannelData)
        for frame in 0 ..< Int(frameCount) {
            let sample = amplitude * Float(
                sin(2 * Double.pi * 80 * Double(frame) / format.sampleRate)
            )
            channels[0][frame] = sample
            channels[1][frame] = sample
        }
        return buffer
    }
}

private enum CoordinatorBassLifecycle {
    case acceptedLoadActivation
    case resumeActivation
    case seek
    case sameBackendRoute
    case equalSampleSeekWithStaleCompletion
}
