import AVFAudio
import Foundation
import Synchronization

typealias PCMBassTap = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

nonisolated func makePCMBassTap(
    analyzer: PCMBassAnalyzer
) -> PCMBassTap {
    { buffer, _ in
        analyzer.process(buffer)
    }
}

protocol PlaybackBassLevelProviding: Sendable {
    func currentBassLevel() -> Float
}

final class PCMBassLevelMeter: PlaybackBassLevelProviding, Sendable {
    private let levelBits = Atomic<UInt32>(0)

    func currentBassLevel() -> Float {
        Float(
            bitPattern: levelBits.load(ordering: .relaxed)
        )
    }

    func store(_ level: Float) {
        levelBits.store(
            min(max(level, 0), 1).bitPattern,
            ordering: .relaxed
        )
    }
}

struct PCMBassEnergyFilter {
    private static let highPassCutoffFrequency = 32.0
    private static let lowPassCutoffFrequency = 160.0
    private static let noiseFloor: Float = 0.002
    private static let minimumReferenceLevel: Float = 0.006
    private static let referenceAttackDuration = 2.0
    private static let referenceReleaseDuration = 4.0
    private static let attack: Float = 0.72
    private static let release: Float = 0.12

    private let sampleRate: Double
    private var highPassFilter: PCMBiquadFilter
    private var lowPassFilter: PCMBiquadFilter
    private var referenceLevel: Float?
    private var envelope: Float = 0

    init(sampleRate: Double) {
        let safeSampleRate = max(sampleRate, 1)
        self.sampleRate = safeSampleRate
        highPassFilter = PCMBiquadFilter(
            kind: .highPass,
            cutoffFrequency: Self.highPassCutoffFrequency,
            sampleRate: safeSampleRate
        )
        lowPassFilter = PCMBiquadFilter(
            kind: .lowPass,
            cutoffFrequency: Self.lowPassCutoffFrequency,
            sampleRate: safeSampleRate
        )
    }

    mutating func process(samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { buffer in
            processMono(buffer)
        }
    }

    mutating func process(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameCount: Int
    ) -> Float {
        guard channelCount > 0, frameCount > 0 else {
            return updateEnvelope(with: 0)
        }

        var squareSum: Float = 0
        for frame in 0 ..< frameCount {
            var mixedSample: Float = 0
            for channel in 0 ..< channelCount {
                mixedSample += channelData[channel][frame]
            }
            mixedSample /= Float(channelCount)
            let bandPassedSample = bandPassed(mixedSample)
            squareSum += bandPassedSample * bandPassedSample
        }

        return normalizedLevel(
            rootMeanSquare: sqrt(squareSum / Float(frameCount)),
            frameCount: frameCount
        )
    }

    private mutating func processMono(
        _ samples: UnsafeBufferPointer<Float>
    ) -> Float {
        guard !samples.isEmpty else {
            return updateEnvelope(with: 0)
        }

        var squareSum: Float = 0
        for sample in samples {
            let bandPassedSample = bandPassed(sample)
            squareSum += bandPassedSample * bandPassedSample
        }
        return normalizedLevel(
            rootMeanSquare: sqrt(squareSum / Float(samples.count)),
            frameCount: samples.count
        )
    }

    private mutating func normalizedLevel(
        rootMeanSquare: Float,
        frameCount: Int
    ) -> Float {
        guard rootMeanSquare > Self.noiseFloor else {
            return updateEnvelope(with: 0)
        }

        let reference = updateReferenceLevel(
            rootMeanSquare: rootMeanSquare,
            frameCount: frameCount
        )
        let relativeEnergy = rootMeanSquare / reference
        let normalized = min(max((relativeEnergy - 0.45) / 1.3, 0), 1)
        return updateEnvelope(with: normalized)
    }

    private mutating func bandPassed(_ sample: Float) -> Float {
        lowPassFilter.process(highPassFilter.process(sample))
    }

    private mutating func updateReferenceLevel(
        rootMeanSquare: Float,
        frameCount: Int
    ) -> Float {
        guard let referenceLevel else {
            let initialReference = max(
                rootMeanSquare * 0.65,
                Self.minimumReferenceLevel
            )
            referenceLevel = initialReference
            return initialReference
        }

        let duration = rootMeanSquare > referenceLevel
            ? Self.referenceAttackDuration
            : Self.referenceReleaseDuration
        let frameDuration = Double(frameCount) / sampleRate
        let smoothing = Float(1 - exp(-frameDuration / duration))
        let updatedReference = max(
            referenceLevel + (rootMeanSquare - referenceLevel) * smoothing,
            Self.minimumReferenceLevel
        )
        self.referenceLevel = updatedReference
        return updatedReference
    }

    private mutating func updateEnvelope(with level: Float) -> Float {
        let smoothing = level > envelope ? Self.attack : Self.release
        envelope += (level - envelope) * smoothing
        return envelope
    }
}

private struct PCMBiquadFilter {
    enum Kind {
        case highPass
        case lowPass
    }

    private let b0: Float
    private let b1: Float
    private let b2: Float
    private let a1: Float
    private let a2: Float
    private var z1: Float = 0
    private var z2: Float = 0

    init(
        kind: Kind,
        cutoffFrequency: Double,
        sampleRate: Double
    ) {
        let omega = 2 * Double.pi * cutoffFrequency / sampleRate
        let cosine = cos(omega)
        let alpha = sin(omega) / (2 * sqrt(0.5))
        let a0 = 1 + alpha
        let numerator0: Double
        let numerator1: Double
        let numerator2: Double
        switch kind {
        case .highPass:
            numerator0 = (1 + cosine) / 2
            numerator1 = -(1 + cosine)
            numerator2 = (1 + cosine) / 2
        case .lowPass:
            numerator0 = (1 - cosine) / 2
            numerator1 = 1 - cosine
            numerator2 = (1 - cosine) / 2
        }
        b0 = Float(numerator0 / a0)
        b1 = Float(numerator1 / a0)
        b2 = Float(numerator2 / a0)
        a1 = Float(-2 * cosine / a0)
        a2 = Float((1 - alpha) / a0)
    }

    mutating func process(_ sample: Float) -> Float {
        let output = sample * b0 + z1
        z1 = sample * b1 - output * a1 + z2
        z2 = sample * b2 - output * a2
        return output
    }
}

struct PlaybackBassEnvelope: Sendable {
    let samplesPerSecond: Double
    let levels: [Float]

    func level(at time: TimeInterval) -> Float {
        guard !levels.isEmpty, time.isFinite, time >= 0 else {
            return 0
        }
        let position = time * samplesPerSecond
        let lowerIndex = min(Int(position), levels.count - 1)
        let upperIndex = min(lowerIndex + 1, levels.count - 1)
        let fraction = Float(position - Double(lowerIndex))
        return levels[lowerIndex]
            + (levels[upperIndex] - levels[lowerIndex]) * fraction
    }
}

enum PlaybackBassEnvelopeAnalyzer {
    static let samplesPerSecond = 60.0

    static func analyze(url: URL) throws -> PlaybackBassEnvelope {
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.processingFormat.sampleRate
        let framesPerSample = AVAudioFrameCount(
            max(sampleRate / samplesPerSecond, 1)
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: framesPerSample
        ) else {
            return PlaybackBassEnvelope(
                samplesPerSecond: samplesPerSecond,
                levels: []
            )
        }

        var filter = PCMBassEnergyFilter(sampleRate: sampleRate)
        var levels: [Float] = []
        levels.reserveCapacity(
            Int(Double(file.length) / max(sampleRate, 1) * samplesPerSecond)
        )

        while file.framePosition < file.length {
            if Task.isCancelled {
                throw CancellationError()
            }
            try file.read(into: buffer, frameCount: framesPerSample)
            guard buffer.frameLength > 0,
                  let channelData = buffer.floatChannelData else {
                break
            }
            levels.append(
                filter.process(
                    channelData: channelData,
                    channelCount: Int(buffer.format.channelCount),
                    frameCount: Int(buffer.frameLength)
                )
            )
        }

        return PlaybackBassEnvelope(
            samplesPerSecond: samplesPerSecond,
            levels: levels
        )
    }
}

final class PCMBassAnalyzer: @unchecked Sendable {
    private let meter: PCMBassLevelMeter
    private let resetRequested = Atomic<Bool>(false)
    private var filter: PCMBassEnergyFilter?
    private var sampleRate: Double = 0

    init(meter: PCMBassLevelMeter) {
        self.meter = meter
    }

    func reset() {
        resetRequested.store(true, ordering: .releasing)
        meter.store(0)
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        if resetRequested.exchange(
            false,
            ordering: .acquiringAndReleasing
        ) {
            filter = nil
            sampleRate = 0
        }
        guard let channelData = buffer.floatChannelData else {
            meter.store(0)
            return
        }

        let bufferSampleRate = buffer.format.sampleRate
        if filter == nil || sampleRate != bufferSampleRate {
            filter = PCMBassEnergyFilter(sampleRate: bufferSampleRate)
            sampleRate = bufferSampleRate
        }
        guard var filter else {
            meter.store(0)
            return
        }

        let level = filter.process(
            channelData: channelData,
            channelCount: Int(buffer.format.channelCount),
            frameCount: Int(buffer.frameLength)
        )
        self.filter = filter
        meter.store(level)
    }
}
