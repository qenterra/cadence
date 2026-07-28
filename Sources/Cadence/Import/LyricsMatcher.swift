import Foundation

enum LyricsMatch: Equatable, Sendable {
    case none
    case matched(URL)
    case ambiguous([URL])
}

struct LyricsMatcher: Sendable {
    func match(
        audio: ScannedSourceFile,
        among files: [ScannedSourceFile]
    ) -> LyricsMatch {
        guard case .audio = audio.kind else {
            return .none
        }

        let audioDirectory = audio.url
            .deletingLastPathComponent()
            .standardizedFileURL
        let normalizedAudioName = normalizedBasename(audio.url)
        let matches = files.compactMap { file -> URL? in
            guard
                file.kind == .lyrics,
                file.url.deletingLastPathComponent().standardizedFileURL
                == audioDirectory,
                normalizedBasename(file.url) == normalizedAudioName
            else {
                return nil
            }
            return file.url.standardizedFileURL
        }
        .sorted { $0.path < $1.path }

        switch matches.count {
        case 0:
            return .none
        case 1:
            return .matched(matches[0])
        default:
            return .ambiguous(matches)
        }
    }

    private func normalizedBasename(
        _ url: URL
    ) -> String {
        url.deletingPathExtension()
            .lastPathComponent
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}
