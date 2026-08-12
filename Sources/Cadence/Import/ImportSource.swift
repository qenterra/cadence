import Foundation

struct ImportSource: Equatable, Sendable {
    let urls: [URL]

    init(urls: [URL]) {
        self.urls = urls.map(\.standardizedFileURL)
    }
}

enum SupportedAudioFormat: String, CaseIterable, Codable, Sendable {
    case aac
    case aif
    case aiff
    case flac
    case m4a
    case mp3
    case wav

    static let supportedPathExtensions = Set(allCases.map(\.rawValue))

    init?(pathExtension: String) {
        self.init(rawValue: pathExtension.lowercased())
    }
}

enum ScannedSourceFileKind: Equatable, Sendable {
    case audio(SupportedAudioFormat)
    case lyrics
}

struct ScannedSourceFile: Equatable, Sendable {
    let url: URL
    let relativePath: String
    let kind: ScannedSourceFileKind
}
