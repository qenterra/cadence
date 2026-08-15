import AVFAudio
import Foundation
import Synchronization

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
    private static let lowerCutoffFrequency = 35.0
    private static let upperCutoffFrequency = 140.0
    private static let noiseFloor: Float = 0.008
    private static let referenceLevel: Float = 0.18
    private static let attack: Float = 0.72
    private static let release: Float = 0.12

    private let lowerCoefficient: Float
    private let upperCoefficient: Float
    private var lowerLowPassedSample: Float = 0
    private var upperLowPassedSample: Float = 0
    private var envelope: Float = 0

    init(sampleRate: Double) {
        let safeSampleRate = max(sampleRate, 1)
        lowerCoefficient = Float(
            1 - exp(
                -2 * Double.pi * Self.lowerCutoffFrequency / safeSampleRate
            )
        )
        upperCoefficient = Float(
            1 - exp(
                -2 * Double.pi * Self.upperCutoffFrequency / safeSampleRate
            )
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
            rootMeanSquare: sqrt(squareSum / Float(frameCount))
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
            rootMeanSquare: sqrt(squareSum / Float(samples.count))
        )
    }

    private mutating func normalizedLevel(
        rootMeanSquare: Float
    ) -> Float {
        let normalized = min(
            max(
                (rootMeanSquare - Self.noiseFloor)
                    / (Self.referenceLevel - Self.noiseFloor),
                0
            ),
            1
        )
        return updateEnvelope(with: normalized)
    }

    private mutating func bandPassed(_ sample: Float) -> Float {
        lowerLowPassedSample += lowerCoefficient
            * (sample - lowerLowPassedSample)
        upperLowPassedSample += upperCoefficient
            * (sample - upperLowPassedSample)
        return upperLowPassedSample - lowerLowPassedSample
    }

    private mutating func updateEnvelope(with level: Float) -> Float {
        let smoothing = level > envelope ? Self.attack : Self.release
        envelope += (level - envelope) * smoothing
        return envelope
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
    private var filter: PCMBassEnergyFilter?
    private var sampleRate: Double = 0

    init(meter: PCMBassLevelMeter) {
        self.meter = meter
    }

    func process(_ buffer: AVAudioPCMBuffer) {
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
