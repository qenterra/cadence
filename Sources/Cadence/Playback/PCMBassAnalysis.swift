import AVFAudio
import Foundation
import Synchronization

typealias PCMBassTap = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

nonisolated func makePCMBassTap(
    analyzer: PCMBassAnalyzer
) -> PCMBassTap {
    { buffer, time in
        analyzer.process(buffer, at: time)
    }
}

protocol PlaybackBassLevelProviding: Sendable {
    func currentBassLevel() -> Float
}

final class PCMBassLevelMeter: PlaybackBassLevelProviding, Sendable {
    private let publication = Atomic<UInt64>(0)

    func currentBassLevel() -> Float {
        Self.level(from: publication.load(ordering: .acquiring))
    }

    func store(_ level: Float) {
        while true {
            let current = publication.load(ordering: .acquiring)
            let desired = Self.pack(
                epoch: Self.epoch(from: current),
                level: level
            )
            guard !publication.compareExchange(
                expected: current,
                desired: desired,
                ordering: .acquiringAndReleasing
            ).exchanged else {
                return
            }
        }
    }

    func publicationEpoch() -> UInt32 {
        Self.epoch(from: publication.load(ordering: .acquiring))
    }

    @discardableResult
    func store(
        _ level: Float,
        ifPublicationEpoch expectedEpoch: UInt32
    ) -> Bool {
        while true {
            let current = publication.load(ordering: .acquiring)
            guard Self.epoch(from: current) == expectedEpoch else {
                return false
            }
            let desired = Self.pack(epoch: expectedEpoch, level: level)
            guard !publication.compareExchange(
                expected: current,
                desired: desired,
                ordering: .acquiringAndReleasing
            ).exchanged else {
                return true
            }
        }
    }

    @discardableResult
    func resetPublication() -> UInt32 {
        while true {
            let current = publication.load(ordering: .acquiring)
            let nextEpoch = Self.epoch(from: current) &+ 1
            guard !publication.compareExchange(
                expected: current,
                desired: Self.pack(epoch: nextEpoch, level: 0),
                ordering: .acquiringAndReleasing
            ).exchanged else {
                return nextEpoch
            }
        }
    }

    @discardableResult
    func resetPublication(
        ifPublicationEpoch expectedEpoch: UInt32
    ) -> UInt32? {
        while true {
            let current = publication.load(ordering: .acquiring)
            guard Self.epoch(from: current) == expectedEpoch else {
                return nil
            }
            let nextEpoch = expectedEpoch &+ 1
            guard !publication.compareExchange(
                expected: current,
                desired: Self.pack(epoch: nextEpoch, level: 0),
                ordering: .acquiringAndReleasing
            ).exchanged else {
                return nextEpoch
            }
        }
    }

    private static func pack(epoch: UInt32, level: Float) -> UInt64 {
        let level = level.isFinite ? min(max(level, 0), 1) : 0
        return UInt64(epoch) << 32 | UInt64(level.bitPattern)
    }

    private static func epoch(from publication: UInt64) -> UInt32 {
        UInt32(truncatingIfNeeded: publication >> 32)
    }

    private static func level(from publication: UInt64) -> Float {
        Float(bitPattern: UInt32(truncatingIfNeeded: publication))
    }
}

private enum PCMBassFilterConstants {
    static let highPassCutoffFrequency = 32.0
    static let lowPassCutoffFrequency = 160.0
}

struct PCMBassEnergyFilter {
    private var firstChannelFilter: PCMBassBandPassFilter
    private var secondChannelFilter: PCMBassBandPassFilter
    private var normalizer: PCMBassEnergyNormalizer

    init(sampleRate: Double) {
        let safeSampleRate = sampleRate.isFinite ? max(sampleRate, 1) : 1
        firstChannelFilter = PCMBassBandPassFilter(sampleRate: safeSampleRate)
        secondChannelFilter = PCMBassBandPassFilter(sampleRate: safeSampleRate)
        normalizer = PCMBassEnergyNormalizer(sampleRate: safeSampleRate)
    }

    mutating func process(samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { samples in
            processMono(samples)
        }
    }

    mutating func process(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameOffset: Int = 0,
        frameCount: Int
    ) -> Float {
        guard channelCount > 0, frameOffset >= 0, frameCount > 0 else {
            return normalizer.process(rootMeanSquare: 0, frameCount: frameCount)
        }

        let analyzedChannelCount = min(channelCount, 2)
        var squareSum: Float = 0
        for relativeFrame in 0 ..< frameCount {
            let frame = frameOffset + relativeFrame
            let firstSample = firstChannelFilter.process(channelData[0][frame])
            squareSum += firstSample * firstSample
            if analyzedChannelCount == 2 {
                let secondSample = secondChannelFilter.process(
                    channelData[1][frame]
                )
                squareSum += secondSample * secondSample
            }
        }

        return normalizer.process(
            rootMeanSquare: sqrt(
                squareSum / Float(frameCount * analyzedChannelCount)
            ),
            frameCount: frameCount
        )
    }

    private mutating func processMono(
        _ samples: UnsafeBufferPointer<Float>
    ) -> Float {
        guard !samples.isEmpty else {
            return normalizer.process(rootMeanSquare: 0, frameCount: 0)
        }

        var squareSum: Float = 0
        for sample in samples {
            let bandPassedSample = firstChannelFilter.process(sample)
            squareSum += bandPassedSample * bandPassedSample
        }
        return normalizer.process(
            rootMeanSquare: sqrt(squareSum / Float(samples.count)),
            frameCount: samples.count
        )
    }
}

private struct PlaybackBassOfflineEnergyFilter {
    private var channelFilters: [PCMBassBandPassFilter]
    private var normalizer: PCMBassEnergyNormalizer

    init(sampleRate: Double, channelCount: Int) {
        let safeSampleRate = sampleRate.isFinite ? max(sampleRate, 1) : 1
        channelFilters = (0 ..< max(channelCount, 1)).map { _ in
            PCMBassBandPassFilter(sampleRate: safeSampleRate)
        }
        normalizer = PCMBassEnergyNormalizer(sampleRate: safeSampleRate)
    }

    mutating func process(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameOffset: Int,
        frameCount: Int
    ) -> Float {
        guard frameOffset >= 0, frameCount > 0 else {
            return normalizer.process(rootMeanSquare: 0, frameCount: frameCount)
        }

        var squareSum: Float = 0
        for relativeFrame in 0 ..< frameCount {
            let frame = frameOffset + relativeFrame
            for channel in channelFilters.indices {
                let sample = channelFilters[channel].process(
                    channelData[channel][frame]
                )
                squareSum += sample * sample
            }
        }
        return normalizer.process(
            rootMeanSquare: sqrt(
                squareSum / Float(frameCount * channelFilters.count)
            ),
            frameCount: frameCount
        )
    }
}

private struct PCMBassEnergyNormalizer {
    private static let noiseFloor: Float = 0.002
    private static let minimumReferenceLevel: Float = 0.006
    private static let referenceAttackDuration = 2.0
    private static let referenceReleaseDuration = 4.0
    private static let attack: Float = 0.72
    private static let release: Float = 0.12

    private let sampleRate: Double
    private var referenceLevel: Float?
    private var envelope: Float = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    mutating func process(
        rootMeanSquare: Float,
        frameCount: Int
    ) -> Float {
        guard rootMeanSquare.isFinite,
              rootMeanSquare > Self.noiseFloor else {
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

    private mutating func updateReferenceLevel(
        rootMeanSquare: Float,
        frameCount: Int
    ) -> Float {
        guard let currentReferenceLevel = referenceLevel else {
            let initialReference = max(
                rootMeanSquare * 0.65,
                Self.minimumReferenceLevel
            )
            referenceLevel = initialReference
            return initialReference
        }

        let duration = rootMeanSquare > currentReferenceLevel
            ? Self.referenceAttackDuration
            : Self.referenceReleaseDuration
        let frameDuration = Double(frameCount) / sampleRate
        let smoothing = Float(1 - exp(-frameDuration / duration))
        let updatedReference = max(
            currentReferenceLevel
                + (rootMeanSquare - currentReferenceLevel) * smoothing,
            Self.minimumReferenceLevel
        )
        referenceLevel = updatedReference
        return updatedReference
    }

    private mutating func updateEnvelope(with level: Float) -> Float {
        let smoothing = level > envelope ? Self.attack : Self.release
        envelope += (level - envelope) * smoothing
        return envelope
    }
}

private struct PCMBassBandPassFilter {
    private var highPassFilter: PCMBiquadFilter
    private var lowPassFilter: PCMBiquadFilter

    init(sampleRate: Double) {
        highPassFilter = PCMBiquadFilter(
            kind: .highPass,
            cutoffFrequency: PCMBassFilterConstants.highPassCutoffFrequency,
            sampleRate: sampleRate
        )
        lowPassFilter = PCMBiquadFilter(
            kind: .lowPass,
            cutoffFrequency: PCMBassFilterConstants.lowPassCutoffFrequency,
            sampleRate: sampleRate
        )
    }

    mutating func process(_ sample: Float) -> Float {
        lowPassFilter.process(highPassFilter.process(sample))
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
        let cutoff = min(max(cutoffFrequency, 0.01), sampleRate * 0.45)
        let omega = 2 * Double.pi * cutoff / sampleRate
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

struct PlaybackBassEnvelope: Equatable, Sendable {
    let samplesPerSecond: Double
    let levels: [Float]

    func level(at time: TimeInterval) -> Float {
        guard !levels.isEmpty,
              samplesPerSecond.isFinite,
              samplesPerSecond > 0,
              time.isFinite,
              time >= 0 else {
            return 0
        }
        let position = time * samplesPerSecond
        let finalIndex = levels.count - 1
        guard position.isFinite,
              position <= Double(finalIndex) else {
            return 0
        }
        let lowerIndex = Int(position)
        let upperIndex = min(lowerIndex + 1, finalIndex)
        let fraction = Float(position - Double(lowerIndex))
        let interpolated = levels[lowerIndex]
            + (levels[upperIndex] - levels[lowerIndex]) * fraction
        return interpolated.isFinite ? min(max(interpolated, 0), 1) : 0
    }
}

protocol PlaybackBassPCMReading: AnyObject {
    var processingFormat: AVAudioFormat { get }
    var length: AVAudioFramePosition { get }
    var framePosition: AVAudioFramePosition { get }

    func read(
        into buffer: AVAudioPCMBuffer,
        frameCount: AVAudioFrameCount
    ) throws
}

extension AVAudioFile: PlaybackBassPCMReading {}

struct PlaybackBassAnalysisPolicy: Equatable, Sendable {
    static let production = PlaybackBassAnalysisPolicy(
        samplesPerSecond: 60,
        readFrameCapacity: 65536,
        maxAnalyzedDuration: 30 * 60,
        maxRetainedLevels: 108_000
    )

    let samplesPerSecond: Double
    let readFrameCapacity: AVAudioFrameCount
    let maxAnalyzedDuration: TimeInterval
    let maxRetainedLevels: Int
}

enum PlaybackBassEnvelopeAnalyzer {
    static func analyze(url: URL) throws -> PlaybackBassEnvelope {
        guard !Task.isCancelled else {
            throw CancellationError()
        }
        let file = try AVAudioFile(forReading: url)
        return try analyze(source: file, policy: .production)
    }

    static func analyze(
        source: any PlaybackBassPCMReading,
        policy: PlaybackBassAnalysisPolicy
    ) throws -> PlaybackBassEnvelope {
        guard !Task.isCancelled else {
            throw CancellationError()
        }
        let format = source.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate.isFinite,
              sampleRate > 0,
              format.channelCount > 0,
              policy.samplesPerSecond.isFinite,
              policy.samplesPerSecond > 0,
              policy.maxAnalyzedDuration.isFinite,
              policy.maxAnalyzedDuration > 0,
              policy.maxRetainedLevels > 0 else {
            return PlaybackBassEnvelope(samplesPerSecond: 0, levels: [])
        }

        let availableFrames = max(source.length - source.framePosition, 0)
        let durationFrameLimit = AVAudioFramePosition(
            min(
                policy.maxAnalyzedDuration * sampleRate,
                Double(AVAudioFramePosition.max)
            )
        )
        let analyzedFrameLimit = min(availableFrames, durationFrameLimit)
        guard analyzedFrameLimit > 0 else {
            return PlaybackBassEnvelope(
                samplesPerSecond: policy.samplesPerSecond,
                levels: []
            )
        }

        let analyzedDuration = Double(analyzedFrameLimit) / sampleRate
        let targetLevelCount = min(
            max(
                Int(ceil(analyzedDuration * policy.samplesPerSecond)),
                1
            ),
            policy.maxRetainedLevels
        )
        let framesPerLevel = max(
            Int(ceil(Double(analyzedFrameLimit) / Double(targetLevelCount))),
            1
        )
        let requestedCapacity = max(Int(policy.readFrameCapacity), 1)
        let windowsPerRead = max(requestedCapacity / framesPerLevel, 1)
        let readFrameCapacity = AVAudioFrameCount(
            framesPerLevel * windowsPerRead
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: readFrameCapacity
        ) else {
            return PlaybackBassEnvelope(
                samplesPerSecond: sampleRate / Double(framesPerLevel),
                levels: []
            )
        }

        return try readEnvelope(
            from: source,
            into: buffer,
            sampleRate: sampleRate,
            analyzedFrameLimit: analyzedFrameLimit,
            targetLevelCount: targetLevelCount,
            framesPerLevel: framesPerLevel,
            readFrameCapacity: readFrameCapacity
        )
    }

    private static func readEnvelope(
        from source: any PlaybackBassPCMReading,
        into buffer: AVAudioPCMBuffer,
        sampleRate: Double,
        analyzedFrameLimit: AVAudioFramePosition,
        targetLevelCount: Int,
        framesPerLevel: Int,
        readFrameCapacity: AVAudioFrameCount
    ) throws -> PlaybackBassEnvelope {
        var filter = PlaybackBassOfflineEnergyFilter(
            sampleRate: sampleRate,
            channelCount: Int(buffer.format.channelCount)
        )
        var levels: [Float] = []
        levels.reserveCapacity(targetLevelCount)
        var analyzedFrames: AVAudioFramePosition = 0
        while analyzedFrames < analyzedFrameLimit,
              levels.count < targetLevelCount {
            guard !Task.isCancelled else {
                throw CancellationError()
            }
            let remainingFrames = analyzedFrameLimit - analyzedFrames
            let requestedFrames = AVAudioFrameCount(
                min(
                    remainingFrames,
                    AVAudioFramePosition(readFrameCapacity)
                )
            )
            buffer.frameLength = 0
            try source.read(into: buffer, frameCount: requestedFrames)
            guard buffer.frameLength > 0,
                  let channelData = buffer.floatChannelData else {
                break
            }
            let deliveredFrames = min(
                Int(buffer.frameLength),
                Int(remainingFrames)
            )
            var frameOffset = 0
            while frameOffset < deliveredFrames,
                  levels.count < targetLevelCount {
                guard !Task.isCancelled else {
                    throw CancellationError()
                }
                let windowFrameCount = min(
                    framesPerLevel,
                    deliveredFrames - frameOffset
                )
                levels.append(filter.process(
                    channelData: channelData,
                    frameOffset: frameOffset,
                    frameCount: windowFrameCount
                ))
                frameOffset += windowFrameCount
            }
            analyzedFrames += AVAudioFramePosition(deliveredFrames)
        }

        return PlaybackBassEnvelope(
            samplesPerSecond: sampleRate / Double(framesPerLevel),
            levels: levels
        )
    }
}

/// The AVAudioEngine-owned tap is the sole caller of `process`; filter and
/// sample-rate state therefore stay render-thread-owned. Main-actor lifecycle
/// changes cross that boundary only through atomics.
final class PCMBassAnalyzer: @unchecked Sendable {
    private struct SuccessorBoundary {
        let sampleTime: UInt64
        let scheduleGeneration: UInt64
        let predecessorTicket: UInt64
    }

    private let meter: PCMBassLevelMeter
    private let successorBoundarySampleTime = Atomic<UInt64>(0)
    private let successorBoundaryScheduleGeneration = Atomic<UInt64>(0)
    private let successorBoundaryTicket = Atomic<UInt64>(0)
    private var filter: PCMBassEnergyFilter?
    private var sampleRate: Double = 0
    private var renderPublicationEpoch: UInt32?
    #if DEBUG
        private let beforePublicationForTesting: (@Sendable () -> Void)?
    #endif

    #if DEBUG
        init(
            meter: PCMBassLevelMeter,
            beforePublicationForTesting: (@Sendable () -> Void)? = nil
        ) {
            self.meter = meter
            self.beforePublicationForTesting = beforePublicationForTesting
        }
    #else
        init(meter: PCMBassLevelMeter) {
            self.meter = meter
        }
    #endif

    func reset() {
        resetAnalysisState()
    }

    func resetAnalysisState() {
        meter.resetPublication()
    }

    func invalidateScheduleBoundary() {
        successorBoundaryTicket.store(0, ordering: .releasing)
    }

    func scheduleSuccessorBoundary(
        at sampleTime: AVAudioFramePosition?,
        scheduleGeneration: UInt64,
        predecessorTicket: UInt64
    ) {
        guard let sampleTime, predecessorTicket != 0 else {
            invalidateScheduleBoundary()
            return
        }
        successorBoundaryTicket.store(0, ordering: .releasing)
        successorBoundarySampleTime.store(
            UInt64(max(sampleTime, 0)),
            ordering: .releasing
        )
        successorBoundaryScheduleGeneration.store(
            scheduleGeneration,
            ordering: .releasing
        )
        successorBoundaryTicket.store(
            predecessorTicket,
            ordering: .releasing
        )
    }

    @discardableResult
    func resetAtSuccessorBoundary(
        _ sampleTime: AVAudioFramePosition?,
        scheduleGeneration: UInt64,
        predecessorTicket: UInt64
    ) -> Bool {
        guard let sampleTime,
              let boundary = successorBoundarySnapshot(),
              boundary.sampleTime == UInt64(max(sampleTime, 0)),
              boundary.scheduleGeneration == scheduleGeneration,
              boundary.predecessorTicket == predecessorTicket else {
            return false
        }
        return consumeSuccessorBoundary(
            boundary,
            resetsPublication: true
        )
    }

    private func successorBoundarySnapshot() -> SuccessorBoundary? {
        let firstTicket = successorBoundaryTicket.load(ordering: .acquiring)
        guard firstTicket != 0 else {
            return nil
        }
        let sampleTime = successorBoundarySampleTime.load(
            ordering: .acquiring
        )
        let scheduleGeneration = successorBoundaryScheduleGeneration.load(
            ordering: .acquiring
        )
        guard successorBoundaryTicket.load(ordering: .acquiring)
            == firstTicket else {
            return nil
        }
        return SuccessorBoundary(
            sampleTime: sampleTime,
            scheduleGeneration: scheduleGeneration,
            predecessorTicket: firstTicket
        )
    }

    private func consumeSuccessorBoundary(
        _ boundary: SuccessorBoundary,
        resetsPublication: Bool
    ) -> Bool {
        let exchange = successorBoundaryTicket.compareExchange(
            expected: boundary.predecessorTicket,
            desired: 0,
            ordering: .acquiringAndReleasing
        )
        guard exchange.exchanged else {
            return false
        }
        if resetsPublication {
            meter.resetPublication()
        }
        return true
    }

    func process(
        _ buffer: AVAudioPCMBuffer,
        at time: AVAudioTime?
    ) {
        var publicationEpoch = meter.publicationEpoch()
        synchronizeRenderState(
            publicationEpoch: publicationEpoch,
            sampleRate: buffer.format.sampleRate
        )
        guard let channelData = buffer.floatChannelData else {
            meter.store(0, ifPublicationEpoch: publicationEpoch)
            return
        }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            meter.store(0, ifPublicationEpoch: publicationEpoch)
            return
        }

        let bufferSampleRate = buffer.format.sampleRate
        guard let time,
              time.isSampleTimeValid,
              time.sampleTime >= 0 else {
            process(
                channelData: channelData,
                channelCount: Int(buffer.format.channelCount),
                frameOffset: 0,
                frameCount: frameCount,
                publicationEpoch: publicationEpoch
            )
            return
        }

        guard let successorBoundary = successorBoundarySnapshot() else {
            process(
                channelData: channelData,
                channelCount: Int(buffer.format.channelCount),
                frameOffset: 0,
                frameCount: frameCount,
                publicationEpoch: publicationEpoch
            )
            return
        }
        let boundary = AVAudioFramePosition(successorBoundary.sampleTime)
        let bufferStart = time.sampleTime
        let bufferEnd = bufferStart + AVAudioFramePosition(frameCount)
        guard bufferEnd > boundary else {
            process(
                channelData: channelData,
                channelCount: Int(buffer.format.channelCount),
                frameOffset: 0,
                frameCount: frameCount,
                publicationEpoch: publicationEpoch
            )
            return
        }

        guard consumeSuccessorBoundary(
            successorBoundary,
            resetsPublication: false
        ) else {
            process(
                channelData: channelData,
                channelCount: Int(buffer.format.channelCount),
                frameOffset: 0,
                frameCount: frameCount,
                publicationEpoch: publicationEpoch
            )
            return
        }

        let prefixCount = min(
            max(Int(boundary - bufferStart), 0),
            frameCount
        )
        if prefixCount > 0 {
            process(
                channelData: channelData,
                channelCount: Int(buffer.format.channelCount),
                frameOffset: 0,
                frameCount: prefixCount,
                publicationEpoch: publicationEpoch
            )
        }
        guard let successorEpoch = meter.resetPublication(
            ifPublicationEpoch: publicationEpoch
        ) else {
            return
        }
        publicationEpoch = successorEpoch
        resetRenderState(
            sampleRate: bufferSampleRate,
            publicationEpoch: publicationEpoch
        )
        let successorCount = frameCount - prefixCount
        if successorCount > 0 {
            process(
                channelData: channelData,
                channelCount: Int(buffer.format.channelCount),
                frameOffset: prefixCount,
                frameCount: successorCount,
                publicationEpoch: publicationEpoch
            )
        }
    }

    private func synchronizeRenderState(
        publicationEpoch: UInt32,
        sampleRate: Double
    ) {
        guard renderPublicationEpoch != publicationEpoch
            || filter == nil
            || self.sampleRate != sampleRate
        else {
            return
        }
        filter = PCMBassEnergyFilter(sampleRate: sampleRate)
        self.sampleRate = sampleRate
        renderPublicationEpoch = publicationEpoch
    }

    private func resetRenderState(
        sampleRate: Double,
        publicationEpoch: UInt32
    ) {
        filter = PCMBassEnergyFilter(sampleRate: sampleRate)
        self.sampleRate = sampleRate
        renderPublicationEpoch = publicationEpoch
    }

    private func process(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameOffset: Int,
        frameCount: Int,
        publicationEpoch: UInt32
    ) {
        guard var filter else {
            meter.store(0, ifPublicationEpoch: publicationEpoch)
            return
        }
        let level = filter.process(
            channelData: channelData,
            channelCount: channelCount,
            frameOffset: frameOffset,
            frameCount: frameCount
        )
        self.filter = filter
        #if DEBUG
            beforePublicationForTesting?()
        #endif
        meter.store(level, ifPublicationEpoch: publicationEpoch)
    }
}
