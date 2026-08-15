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

        backend.handleFinished(trackID: first.track.id)

        #expect(backend.currentItem?.resolved.track.id == second.track.id)
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
        phaseOffset: Int = 0
    ) throws -> ResolvedPlaybackTrack {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: false
            )
        )
        let frameCount = AVAudioFrameCount(1024)
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            )
        )
        buffer.frameLength = frameCount
        let channels = try #require(buffer.floatChannelData)
        for frame in 0 ..< Int(frameCount) {
            let sample = sin(
                Double(frame + phaseOffset) * 2 * .pi * 440 / sampleRate
            )
            channels[0][frame] = Float(sample)
            channels[1][frame] = Float(sample)
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
}
