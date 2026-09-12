import AppKit
import AVFAudio
@testable import Cadence
import Metal
@testable import QenTerraAudioAnalysis
import class QenTerraMediaComponents.ArtworkAccentGradientView
import QuartzCore
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
        let disabled = CadenceModeBassResponse.resolve(
            level: 1,
            reduceMotion: false,
            reactsToBass: false
        )

        #expect(negative == .identity)
        #expect(silence == .identity)
        #expect(peak.artworkScale > 1)
        #expect(peak.artworkScale <= 1.05)
        #expect(overdriven == peak)
        #expect(reduced == .identity)
        #expect(paused == .identity)
        #expect(disabled == .identity)
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
}

extension CadenceModeBassAnalysisTests {
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

    @Test("Cadence Mode leaves unavailable lyrics visually empty")
    func unavailableLyricsStayHidden() {
        #expect(
            CadenceModeLyricContentPresentation.resolve(status: .missing)
                == .hidden
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
    @Test(
        "The Metal terrain covers every fullscreen corner",
        .appKitExclusive
    )
    func metalTerrainCoversFullscreenCorners() {
        let size = CGSize(width: 2560, height: 1400)
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal is unavailable on the test host")
            return
        }
        let view = ArtworkAccentGradientView(
            frame: CGRect(origin: .zero, size: size),
            device: device
        )
        view.update(
            palette: .fixture,
            appearance: .resolve(
                reduceMotion: true,
                reduceTransparency: false,
                increasedContrast: false
            )
        )

        guard let image = view.makeSnapshot(size: size, time: 0) else {
            Issue.record("Metal renderer did not produce a fullscreen frame")
            return
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        let corners = [
            CGPoint(x: 1, y: 1),
            CGPoint(x: bitmap.pixelsWide - 2, y: 1),
            CGPoint(x: 1, y: bitmap.pixelsHigh - 2),
            CGPoint(x: bitmap.pixelsWide - 2, y: bitmap.pixelsHigh - 2),
        ]
        for corner in corners {
            guard let color = bitmap.colorAt(
                x: Int(corner.x),
                y: Int(corner.y)
            )?.usingColorSpace(.deviceRGB) else {
                Issue.record("Metal corner could not be sampled")
                continue
            }
            #expect(
                max(
                    color.redComponent,
                    color.greenComponent,
                    color.blueComponent
                ) > 0.01
            )
            #expect(color.alphaComponent > 0.99)
        }
    }
}

private extension CadenceModeBassAnalysisTests {
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
