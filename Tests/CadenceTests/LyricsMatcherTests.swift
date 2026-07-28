@testable import Cadence
import Foundation
import Testing

struct LyricsMatcherTests {
    @Test("LRC matching is same-folder, Unicode-normalized, and case-insensitive")
    func normalizedSameFolderMatch() {
        let folder = URL(filePath: "/Import/Album")
        let audio = ScannedSourceFile(
            url: folder.appending(path: "ÉCHO.flac"),
            relativePath: "Album/ÉCHO.flac",
            kind: .audio(.flac)
        )
        let matchingLyrics = ScannedSourceFile(
            url: folder.appending(path: "e\u{301}cho.LRC"),
            relativePath: "Album/e\u{301}cho.LRC",
            kind: .lyrics
        )
        let unrelatedLyrics = ScannedSourceFile(
            url: URL(filePath: "/Import/Other/ÉCHO.lrc"),
            relativePath: "Other/ÉCHO.lrc",
            kind: .lyrics
        )

        let result = LyricsMatcher().match(
            audio: audio,
            among: [matchingLyrics, unrelatedLyrics]
        )

        #expect(result == .matched(matchingLyrics.url))
    }

    @Test("Multiple normalized LRC names remain ambiguous")
    func ambiguousMatch() {
        let folder = URL(filePath: "/Import/Album")
        let audio = source(
            folder: folder,
            name: "Écho.flac",
            kind: .audio(.flac)
        )
        let first = source(
            folder: folder,
            name: "ÉCHO.lrc",
            kind: .lyrics
        )
        let second = source(
            folder: folder,
            name: "e\u{301}cho.LRC",
            kind: .lyrics
        )

        let result = LyricsMatcher().match(
            audio: audio,
            among: [second, first]
        )

        #expect(
            result == .ambiguous(
                [first.url, second.url].sorted { $0.path < $1.path }
            )
        )
    }

    @Test("Missing same-folder LRC stays unmatched")
    func missingMatch() {
        let audio = source(
            folder: URL(filePath: "/Import/Album"),
            name: "Track.wav",
            kind: .audio(.wav)
        )

        #expect(LyricsMatcher().match(audio: audio, among: []) == .none)
    }

    private func source(
        folder: URL,
        name: String,
        kind: ScannedSourceFileKind
    ) -> ScannedSourceFile {
        ScannedSourceFile(
            url: folder.appending(path: name),
            relativePath: "Album/\(name)",
            kind: kind
        )
    }
}
