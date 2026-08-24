import AppKit
import AVFAudio
@testable import Cadence
import QuartzCore
import Synchronization
import Testing

struct CadenceModeBassAnalysisTests {
    @Test("Bass response is clamped, bounded, and motion-safe")
    func bassResponseIsBounded() {
        let negative = CadenceModeBassResponse.resolve(
            level: -1,
            reduceMotion: false
        )
        let silence = CadenceModeBassResponse.resolve(
            level: 0,
            reduceMotion: false
        )
        let peak = CadenceModeBassResponse.resolve(
            level: 1,
            reduceMotion: false
        )
        let overdriven = CadenceModeBassResponse.resolve(
            level: 5,
            reduceMotion: false
        )
        let reduced = CadenceModeBassResponse.resolve(
            level: 1,
            reduceMotion: true
        )
        let paused = CadenceModeBassResponse.resolve(
            level: 1,
            reduceMotion: false,
            isPlaying: false
        )

        #expect(negative == .identity)
        #expect(silence == .identity)
        #expect(peak.artworkScale > 1)
        #expect(peak.artworkScale <= 1.05)
        #expect(overdriven == peak)
        #expect(reduced == .identity)
        #expect(paused == .identity)
    }

    @MainActor
    @Test("Bass smoother attacks quickly, releases slowly, clamps jumps, and resets")
    func bassArtworkResponseIsSmoothed() {
        let smoother = CadenceModeBassSmoother()
        let trackID = UUID()
        let first = smoother.resolve(
            trackID: trackID,
            target: 1,
            timestamp: 0
        )
        let second = smoother.resolve(
            trackID: trackID,
            target: 1,
            timestamp: 1.0 / 120.0
        )
        let release = smoother.resolve(
            trackID: trackID,
            target: 0,
            timestamp: 2.0 / 120.0
        )
        let jump = smoother.resolve(
            trackID: trackID,
            target: 0,
            timestamp: 20
        )

        #expect(first > 0.5)
        #expect(first < second)
        #expect(second < 1)
        #expect(release < second)
        #expect(release > second * 0.85)
        #expect(jump > 0)
        #expect(smoother.reset(trackID: trackID) == 0)
        #expect(
            smoother.resolve(
                trackID: trackID,
                target: 0,
                timestamp: 21
            ) == 0
        )
    }

    @MainActor
    @Test("A new track synchronously clears the predecessor release tail")
    func bassArtworkResponseIsTrackKeyed() {
        let smoother = CadenceModeBassSmoother()
        let predecessorID = UUID()
        let successorID = UUID()
        _ = smoother.resolve(
            trackID: predecessorID,
            target: 1,
            timestamp: 0
        )
        _ = smoother.resolve(
            trackID: predecessorID,
            target: 1,
            timestamp: 1.0 / 120.0
        )

        let successorFirstFrame = smoother.resolve(
            trackID: successorID,
            target: 0,
            timestamp: 2.0 / 120.0
        )

        #expect(successorFirstFrame == 0)
    }

    @Test("Sustained bass dominates upper mids while silence stays at zero")
    func bassFilterPrefersLowFrequencies() {
        let bassLevel = normalizedBassLevel(
            frequency: 80,
            amplitude: 0.35
        )
        let upperMidLevel = normalizedBassLevel(
            frequency: 1200,
            amplitude: 0.35
        )
        let silenceLevel = normalizedBassLevel(
            frequency: 80,
            amplitude: 0
        )

        #expect(bassLevel > 0.2)
        #expect(bassLevel > upperMidLevel * 2)
        #expect((0 ... 1).contains(bassLevel))
        #expect(silenceLevel == 0)
    }

    @Test("Adaptive normalization keeps quiet and loud masters legible")
    func bassFilterAdaptsToTrackLoudness() {
        let quietLevel = normalizedBassLevel(
            frequency: 80,
            amplitude: 0.055
        )
        let loudLevel = normalizedBassLevel(
            frequency: 80,
            amplitude: 0.35
        )

        #expect(quietLevel > 0.2)
        #expect(abs(quietLevel - loudLevel) < 0.15)
    }

    @Test("Stereo bass energy is invariant to channel polarity")
    func bassFilterCombinesChannelPower() throws {
        let inPhase = try normalizedStereoBassLevel(
            frequency: 80,
            amplitude: 0.35,
            rightPolarity: 1
        )
        let inverted = try normalizedStereoBassLevel(
            frequency: 80,
            amplitude: 0.35,
            rightPolarity: -1
        )
        let upperMid = try normalizedStereoBassLevel(
            frequency: 1200,
            amplitude: 0.35,
            rightPolarity: -1
        )
        let silence = try normalizedStereoBassLevel(
            frequency: 80,
            amplitude: 0,
            rightPolarity: -1
        )

        #expect(inPhase > 0.2)
        #expect(inverted > 0.2)
        #expect(abs(inPhase - inverted) < 0.02)
        #expect(inverted > upperMid * 2)
        #expect(silence == 0)
    }

    @Test("Analyzer reset makes a reused analyzer match a fresh track")
    func bassAnalyzerResetsBetweenTracks() throws {
        let format = try #require(
            AVAudioFormat(
                standardFormatWithSampleRate: 48000,
                channels: 1
            )
        )
        let loud = try sineBuffer(
            format: format,
            frequency: 80,
            amplitude: 0.35,
            frameCount: 1024
        )
        let quiet = try sineBuffer(
            format: format,
            frequency: 80,
            amplitude: 0.055,
            frameCount: 1024
        )
        let reusedMeter = PCMBassLevelMeter()
        let reusedAnalyzer = PCMBassAnalyzer(meter: reusedMeter)
        for _ in 0 ..< 240 {
            reusedAnalyzer.process(loud, at: nil)
        }

        reusedAnalyzer.reset()
        reusedAnalyzer.process(quiet, at: nil)

        let freshMeter = PCMBassLevelMeter()
        let freshAnalyzer = PCMBassAnalyzer(meter: freshMeter)
        freshAnalyzer.process(quiet, at: nil)

        #expect(
            abs(reusedMeter.currentBassLevel() - freshMeter.currentBassLevel())
                < 0.001
        )
    }

    @Test("Detached sendable tap publishes without an actor hop")
    func bassTapIsDetachedAndSendable() async throws {
        let format = try #require(
            AVAudioFormat(
                standardFormatWithSampleRate: 48000,
                channels: 1
            )
        )
        let buffer = try sineBuffer(
            format: format,
            frequency: 80,
            amplitude: 0.35,
            frameCount: 4800
        )
        let meter = PCMBassLevelMeter()
        let analyzer = PCMBassAnalyzer(meter: meter)
        let tap: PCMBassTap = makePCMBassTap(analyzer: analyzer)

        await Task.detached {
            tap(
                buffer,
                AVAudioTime(sampleTime: 0, atRate: format.sampleRate)
            )
        }.value

        #expect(meter.currentBassLevel() > 0)
    }

    @Test("A reset epoch rejects an already-running tap publication")
    func bassResetFencesInflightPublication() throws {
        let format = try #require(
            AVAudioFormat(
                standardFormatWithSampleRate: 48000,
                channels: 1
            )
        )
        let buffer = try sineBuffer(
            format: format,
            frequency: 80,
            amplitude: 0.35,
            frameCount: 4800
        )
        let meter = PCMBassLevelMeter()
        let gate = BassPublicationGate()
        let analyzer = PCMBassAnalyzer(
            meter: meter,
            beforePublicationForTesting: { @Sendable in
                gate.suspendOnce()
            }
        )
        let tap = makePCMBassTap(analyzer: analyzer)
        let callbackFinished = DispatchSemaphore(value: 0)
        let callbackInput = SendableBassCallbackInput(
            buffer: buffer,
            time: AVAudioTime(sampleTime: 0, atRate: format.sampleRate)
        )
        DispatchQueue.global().async {
            tap(callbackInput.buffer, callbackInput.time)
            callbackFinished.signal()
        }
        let didReachPublication = waitForSemaphore(
            gate.reachedPublication,
            timeout: .now() + 2
        )
        #expect(didReachPublication)

        analyzer.reset()
        analyzer.reset()
        gate.releasePublication.signal()
        #expect(
            waitForSemaphore(
                callbackFinished,
                timeout: .now() + 2
            )
        )

        #expect(meter.currentBassLevel() == 0)
        analyzer.process(buffer, at: nil)
        #expect(meter.currentBassLevel() > 0)
    }
}

extension CadenceModeBassAnalysisTests {
    @Test("Native envelopes interpolate only within finite sample bounds")
    func bassEnvelopeInterpolationIsSafe() {
        let envelope = PlaybackBassEnvelope(
            samplesPerSecond: 2,
            levels: [0, 1, 0.25]
        )
        let empty = PlaybackBassEnvelope(
            samplesPerSecond: 2,
            levels: []
        )

        #expect(envelope.level(at: 0) == 0)
        #expect(envelope.level(at: 0.25) == 0.5)
        #expect(envelope.level(at: 0.5) == 1)
        #expect(envelope.level(at: 1) == 0.25)
        #expect(envelope.level(at: -0.1) == 0)
        #expect(envelope.level(at: .nan) == 0)
        #expect(envelope.level(at: .infinity) == 0)
        #expect(envelope.level(at: 1.001) == 0)
        #expect(empty.level(at: 0) == 0)
    }

    @Test("Default Native loader analyzes a bounded real WAV and cancels")
    func defaultNativeBassLoaderRealWave() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Native-Bass-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let duration = 2.0
        let bassURL = directory.appending(path: "bass.wav")
        let upperMidURL = directory.appending(path: "upper-mid.wav")
        try writeStereoWave(
            to: bassURL,
            frequency: 80,
            duration: duration,
            rightPolarity: -1
        )
        try writeStereoWave(
            to: upperMidURL,
            frequency: 1200,
            duration: duration,
            rightPolarity: -1
        )

        let bass = try #require(
            await defaultPlaybackBassEnvelopeLoader(bassURL)
        )
        let upperMid = try #require(
            await defaultPlaybackBassEnvelopeLoader(upperMidURL)
        )
        let bassTail = bass.levels.suffix(30)
        let upperMidTail = upperMid.levels.suffix(30)
        let bassAverage = bassTail.reduce(0, +) / Float(bassTail.count)
        let upperMidAverage = upperMidTail.reduce(0, +)
            / Float(upperMidTail.count)

        #expect(!bass.levels.isEmpty)
        #expect(
            bass.levels.count
                <= PlaybackBassAnalysisPolicy.production.maxRetainedLevels
        )
        #expect(bassAverage > 0.2)
        #expect(bassAverage > upperMidAverage * 2)
        #expect(bass.level(at: duration - 1.0 / 60.0) > 0)
        #expect(bass.level(at: duration) == 0)

        let cancelled = await Task.detached {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return await defaultPlaybackBassEnvelopeLoader(bassURL)
        }.value
        #expect(cancelled == nil)
    }

    @Test("Native analysis caps reads, analyzed frames, and retained levels")
    func nativeBassAnalysisIsBounded() throws {
        let source = try CountingBassPCMSource(
            sampleRate: 48000,
            channelCount: 2,
            length: 48000 * 60 * 60 * 10,
            frequency: 80
        )
        let policy = PlaybackBassAnalysisPolicy(
            samplesPerSecond: 60,
            readFrameCapacity: 65536,
            maxAnalyzedDuration: 2,
            maxRetainedLevels: 120
        )

        let envelope = try PlaybackBassEnvelopeAnalyzer.analyze(
            source: source,
            policy: policy
        )

        #expect(source.readCount <= 2)
        #expect(source.framePosition == 96000)
        #expect(envelope.levels.count <= policy.maxRetainedLevels)
        #expect(envelope.levels.count == 120)
        #expect(envelope.levels.suffix(30).allSatisfy { $0 > 0.2 })
        #expect(envelope.level(at: 2) == 0)
    }
}

struct CadenceModeRegressionTests {
    @Test("Production nil readiness observer installs no geometry tracking")
    func visualReadinessGeometryIsObserverConditional() {
        var installationCount = 0
        let observer = CadenceModeVisualReadinessObserver(
            artworkReady: { _ in },
            render: { _ in }
        )

        #expect(
            CadenceModeVisualReadinessGeometryPolicy.observerToInstall(
                nil,
                countInstallation: { installationCount += 1 }
            ) == nil
        )
        #expect(installationCount == 0)

        let installed = CadenceModeVisualReadinessGeometryPolicy
            .observerToInstall(
                observer,
                countInstallation: { installationCount += 1 }
            )
        #expect(installed === observer)
        #expect(installationCount == 1)
    }

    @Test("Document replacement drops a stale initial lyric target")
    func replacementProjectsExactlyOneValidTarget() {
        let oldLine = LyricLine(text: "Old", startTime: 1)
        let newLine = LyricLine(text: "New", startTime: 1)
        let replacement = LyricDocument(
            trackID: UUID(),
            lines: [newLine]
        )
        let initialTarget = LyricDocumentLineProjection.activeLineID(
            oldLine.id,
            in: replacement
        )
        var emission = LyricLineEmissionState(activeLineID: initialTarget)
        let candidates = [initialTarget, newLine.id, newLine.id]
        let targets = candidates.compactMap { candidate -> LyricLine.ID? in
            let projected = LyricDocumentLineProjection.activeLineID(
                candidate,
                in: replacement
            )
            guard emission.update(to: projected) else {
                return nil
            }
            return projected
        }

        #expect(initialTarget == nil)
        #expect(targets == [newLine.id])
        #expect(targets.allSatisfy { target in
            replacement.lines.contains { $0.id == target }
        })
    }

    @Test("Reduce Motion makes lyric emphasis and scrolling identity changes")
    func reduceMotionDisablesLyricAnimations() {
        let reduced = LyricMotionBehavior.resolve(reduceMotion: true)
        let normal = LyricMotionBehavior.resolve(reduceMotion: false)

        #expect(!reduced.animatesEmphasis)
        #expect(!reduced.animatesScroll)
        #expect(normal.animatesEmphasis)
        #expect(normal.animatesScroll)
    }

    @Test("Unavailable lyrics reserve display-scale type for the track")
    func unavailableLyricsTypography() {
        #expect(CadenceModeUnavailableLyricsMetrics.titleSize >= 32)
        #expect(
            CadenceModeUnavailableLyricsMetrics.titleSize
                > CadenceModeUnavailableLyricsMetrics.artistSize
        )
    }

    @Test("Cadence Mode keeps a hard 60 FPS floor and 110 FPS ProMotion target")
    func performancePolicyKeepsSupportedFloor() {
        #expect(
            CadenceModePerformancePolicy.minimumDeliveredFramesPerSecond(
                displayMaximumFramesPerSecond: 60
            ) == 60
        )
        #expect(
            CadenceModePerformancePolicy.minimumDeliveredFramesPerSecond(
                displayMaximumFramesPerSecond: 120
            ) == 110
        )
        #expect(CadenceModePerformancePolicy.maximumFrameDuration <= 0.025)
        #expect(CadenceModePerformancePolicy.maximumInputLatency <= 0.010)
        let sixtyHertzRange = CadenceModePerformancePolicy
            .animationFrameRateRange(displayMaximumFramesPerSecond: 60)
        let proMotionRange = CadenceModePerformancePolicy
            .animationFrameRateRange(displayMaximumFramesPerSecond: 120)
        let backgroundRange = CadenceModePerformancePolicy
            .animationFrameRateRange(
                displayMaximumFramesPerSecond: 120,
                contentMaximumFramesPerSecond: 60
            )
        #expect(sixtyHertzRange.minimum == 60)
        #expect(sixtyHertzRange.preferred == 60)
        #expect(proMotionRange.minimum == 60)
        #expect(proMotionRange.preferred == 120)
        #expect(backgroundRange.minimum == 60)
        #expect(backgroundRange.preferred == 60)
    }

    @MainActor
    @Test("Late artwork preparation preserves a pulse already on screen")
    func lateArtworkPreparationPreservesLiveEffects() async {
        let store = RhythmPulseStore()
        store.registerHit(
            lane: .left,
            emitterOrigin: CGPoint(x: 0.34, y: 0.38)
        )
        let washIDs = store.renderWashes.map(\.id)
        let particleIDs = store.renderParticles.map(\.id)

        await store.prepare(asset: nil)

        #expect(!washIDs.isEmpty)
        #expect(!particleIDs.isEmpty)
        #expect(store.renderWashes.map(\.id) == washIDs)
        #expect(store.renderParticles.map(\.id) == particleIDs)
    }

    @MainActor
    @Test("The rotating background field covers every fullscreen corner")
    func rotatingBackgroundCoversFullscreenCorners() throws {
        let canvas = CGRect(x: 0, y: 0, width: 2560, height: 1400)
        let view = CadenceModeBackgroundView(frame: canvas)
        view.update(
            palette: .fixture,
            appearance: .resolve(
                reduceMotion: false,
                reduceTransparency: false,
                increasedContrast: false
            )
        )
        view.layoutSubtreeIfNeeded()

        let conicLayer = try #require(
            view.layer?.sublayers?
                .compactMap { $0 as? CAGradientLayer }
                .first { $0.type == .conic }
        )
        let minimumScale = 1.02
        let farthestHorizontalEdge = canvas.width * 0.56
        let farthestVerticalEdge = canvas.height * 0.57

        #expect(
            conicLayer.bounds.width * minimumScale / 2
                >= farthestHorizontalEdge + 2
        )
        #expect(
            conicLayer.bounds.height * minimumScale / 2
                >= farthestVerticalEdge + 2
        )
        #expect(conicLayer.shouldRasterize)
        #expect(!conicLayer.drawsAsynchronously)
        let animatedKeyPaths = conicLayer.animationKeys()?.flatMap { key in
            (conicLayer.animation(forKey: key) as? CAAnimationGroup)?
                .animations?
                .compactMap { ($0 as? CAPropertyAnimation)?.keyPath } ?? []
        } ?? []
        #expect(!animatedKeyPaths.contains("transform.rotation.z"))
    }
}

private final class BassPublicationGate: @unchecked Sendable {
    let reachedPublication = DispatchSemaphore(value: 0)
    let releasePublication = DispatchSemaphore(value: 0)

    private let shouldSuspend = Atomic<Bool>(true)

    func suspendOnce() {
        guard shouldSuspend.exchange(
            false,
            ordering: .acquiringAndReleasing
        ) else {
            return
        }
        reachedPublication.signal()
        releasePublication.wait()
    }
}

private final class SendableBassCallbackInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let time: AVAudioTime

    init(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        self.buffer = buffer
        self.time = time
    }
}

private final class CountingBassPCMSource: PlaybackBassPCMReading {
    let processingFormat: AVAudioFormat
    let length: AVAudioFramePosition
    private(set) var framePosition: AVAudioFramePosition = 0
    private(set) var readCount = 0

    private let frequency: Double

    init(
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        length: AVAudioFramePosition,
        frequency: Double
    ) throws {
        processingFormat = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: channelCount,
                interleaved: false
            )
        )
        self.length = length
        self.frequency = frequency
    }

    func read(
        into buffer: AVAudioPCMBuffer,
        frameCount requestedFrameCount: AVAudioFrameCount
    ) throws {
        readCount += 1
        let available = max(length - framePosition, 0)
        let frameCount = min(
            AVAudioFramePosition(requestedFrameCount),
            available,
            AVAudioFramePosition(buffer.frameCapacity)
        )
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard frameCount > 0,
              let channels = buffer.floatChannelData else {
            return
        }
        for frame in 0 ..< Int(frameCount) {
            let sourceFrame = framePosition + AVAudioFramePosition(frame)
            let sample = Float(
                sin(
                    2 * Double.pi * frequency * Double(sourceFrame)
                        / processingFormat.sampleRate
                )
            ) * 0.35
            for channel in 0 ..< Int(processingFormat.channelCount) {
                channels[channel][frame] = channel.isMultiple(of: 2)
                    ? sample
                    : -sample
            }
        }
        framePosition += frameCount
    }
}

private extension CadenceModeBassAnalysisTests {
    func normalizedBassLevel(
        frequency: Double,
        amplitude: Float
    ) -> Float {
        let sampleRate = 48000.0
        let frameCount = 1024
        var filter = PCMBassEnergyFilter(sampleRate: sampleRate)
        var level: Float = 0
        for chunk in 0 ..< 240 {
            let samples = (0 ..< frameCount).map { frame in
                let sample = chunk * frameCount + frame
                return Float(
                    sin(2 * Double.pi * frequency * Double(sample) / sampleRate)
                ) * amplitude
            }
            level = filter.process(samples: samples)
        }
        return level
    }

    func sineBuffer(
        format: AVAudioFormat,
        frequency: Double,
        amplitude: Float,
        frameCount: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            )
        )
        buffer.frameLength = frameCount
        let samples = try #require(buffer.floatChannelData?[0])
        for frame in 0 ..< Int(frameCount) {
            samples[frame] = Float(
                sin(
                    2 * Double.pi * frequency * Double(frame)
                        / format.sampleRate
                )
            ) * amplitude
        }
        return buffer
    }

    func normalizedStereoBassLevel(
        frequency: Double,
        amplitude: Float,
        rightPolarity: Float
    ) throws -> Float {
        let sampleRate = 48000.0
        let frameCount = 4800
        let format = try #require(
            AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 2
            )
        )
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        )
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channels = try #require(buffer.floatChannelData)
        for frame in 0 ..< frameCount {
            let sample = Float(
                sin(2 * Double.pi * frequency * Double(frame) / sampleRate)
            ) * amplitude
            channels[0][frame] = sample
            channels[1][frame] = sample * rightPolarity
        }

        var filter = PCMBassEnergyFilter(sampleRate: sampleRate)
        var level: Float = 0
        for _ in 0 ..< 60 {
            level = filter.process(
                channelData: channels,
                channelCount: 2,
                frameCount: frameCount
            )
        }
        return level
    }

    func writeStereoWave(
        to url: URL,
        frequency: Double,
        duration: TimeInterval,
        rightPolarity: Float
    ) throws {
        let sampleRate = 48000.0
        let frameCount = AVAudioFrameCount(duration * sampleRate)
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
                sin(2 * Double.pi * frequency * Double(frame) / sampleRate)
            ) * 0.35
            channels[0][frame] = sample
            channels[1][frame] = sample * rightPolarity
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    func waitForSemaphore(
        _ semaphore: DispatchSemaphore,
        timeout: DispatchTime
    ) -> Bool {
        semaphore.wait(timeout: timeout) == .success
    }
}

private extension RhythmAccentPalette {
    static let fixture = RhythmAccentPalette(
        colors: [
            RhythmPulseColor(red: 0.86, green: 0.37, blue: 0.66),
            RhythmPulseColor(red: 0.49, green: 0.38, blue: 1),
            RhythmPulseColor(red: 0, green: 0.8, blue: 0.89),
        ]
    )
}
