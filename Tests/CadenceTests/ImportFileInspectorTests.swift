import AVFoundation
@testable import Cadence
import Foundation
import Testing

struct ImportFileInspectorTests {
    @Test("A valid same-folder LRC is linked after line-level validation")
    func validLyrics() async throws {
        let fixture = try ImportInspectorFixture()
        defer {
            fixture.remove()
        }
        let lyricURL = fixture.root.appending(path: "Signal.lrc")
        try "[00:01.00]First line".write(
            to: lyricURL,
            atomically: true,
            encoding: .utf8
        )
        let files = [
            fixture.audio,
            ScannedSourceFile(
                url: lyricURL,
                relativePath: "Signal.lrc",
                kind: .lyrics
            ),
        ]

        let draft = try await ImportFileInspector().inspect(
            audio: fixture.audio,
            among: files
        )

        #expect(draft.failure == nil)
        #expect(draft.contentHash?.count == 64)
        #expect(draft.lyrics == .linked(lyricURL))
    }

    @Test("Malformed lyrics stay non-blocking and preserve valid audio")
    func malformedLyrics() async throws {
        let fixture = try ImportInspectorFixture()
        defer {
            fixture.remove()
        }
        let lyricURL = fixture.root.appending(path: "Signal.lrc")
        try "not timed lyrics".write(
            to: lyricURL,
            atomically: true,
            encoding: .utf8
        )
        let files = [
            fixture.audio,
            ScannedSourceFile(
                url: lyricURL,
                relativePath: "Signal.lrc",
                kind: .lyrics
            ),
        ]

        let draft = try await ImportFileInspector().inspect(
            audio: fixture.audio,
            among: files
        )

        #expect(draft.failure == nil)
        #expect(draft.metadata != nil)
        guard case .malformed = draft.lyrics else {
            Issue.record("Expected malformed lyrics without an audio failure.")
            return
        }
    }

    @Test("Ambiguous lyrics are reported without guessing or reading a winner")
    func ambiguousLyrics() async throws {
        let fixture = try ImportInspectorFixture()
        defer {
            fixture.remove()
        }
        let first = fixture.root.appending(path: "SIGNAL.lrc")
        let second = fixture.root.appending(path: "Signal.LRC")
        let files = [
            fixture.audio,
            ScannedSourceFile(
                url: first,
                relativePath: "SIGNAL.lrc",
                kind: .lyrics
            ),
            ScannedSourceFile(
                url: second,
                relativePath: "Signal.LRC",
                kind: .lyrics
            ),
        ]

        let draft = try await ImportFileInspector().inspect(
            audio: fixture.audio,
            among: files
        )

        #expect(draft.failure == nil)
        #expect(draft.lyrics == .ambiguous([first, second]))
    }

    @Test("A disappeared source remains a blocking Review candidate")
    func disappearedSource() async throws {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "Missing-\(UUID().uuidString).wav"
        )
        let audio = ScannedSourceFile(
            url: url,
            relativePath: url.lastPathComponent,
            kind: .audio(.wav)
        )

        let draft = try await ImportFileInspector().inspect(
            audio: audio,
            among: [audio]
        )

        #expect(draft.failure != nil)
        #expect(draft.metadata == nil)
        #expect(draft.contentHash == nil)
    }
}

private struct ImportInspectorFixture {
    let root: URL
    let audio: ScannedSourceFile

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Inspector-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let audioURL = root.appending(path: "Signal.wav")
        try Self.writeSilentWAV(to: audioURL)
        audio = ScannedSourceFile(
            url: audioURL,
            relativePath: "Signal.wav",
            kind: .audio(.wav)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func writeSilentWAV(
        to url: URL
    ) throws {
        let format = try #require(
            AVAudioFormat(
                standardFormatWithSampleRate: 44100,
                channels: 2
            )
        )
        let frameCount: AVAudioFrameCount = 441
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            )
        )
        buffer.frameLength = frameCount

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings
        )
        try file.write(from: buffer)
    }
}
