import Foundation

protocol ImportFileInspecting: Sendable {
    func inspect(
        audio: ScannedSourceFile,
        among files: [ScannedSourceFile]
    ) async throws -> ImportInspectionDraft
}

struct ImportFileInspector: ImportFileInspecting {
    private let metadataReader: MetadataReader
    private let hasher: ContentHasher
    private let lyricsMatcher: LyricsMatcher

    init(
        metadataReader: MetadataReader = MetadataReader(),
        hasher: ContentHasher = ContentHasher(),
        lyricsMatcher: LyricsMatcher = LyricsMatcher()
    ) {
        self.metadataReader = metadataReader
        self.hasher = hasher
        self.lyricsMatcher = lyricsMatcher
    }

    func inspect(
        audio: ScannedSourceFile,
        among files: [ScannedSourceFile]
    ) async throws -> ImportInspectionDraft {
        try Task.checkCancellation()

        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: audio.url.path
            )
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let metadata = try await metadataReader.read(url: audio.url)
            let contentHash = try await hasher.sha256(of: audio.url)
            let lyrics = lyricsInspection(
                audio: audio,
                among: files,
                embedded: metadata.embeddedLyrics
            )

            return ImportInspectionDraft(
                sourceFile: audio,
                sizeInBytes: size,
                metadata: metadata,
                contentHash: contentHash,
                lyrics: lyrics,
                failure: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ImportInspectionDraft(
                sourceFile: audio,
                sizeInBytes: 0,
                metadata: nil,
                contentHash: nil,
                lyrics: .unavailable,
                failure: .unreadableSource(error.localizedDescription)
            )
        }
    }

    private func lyricsInspection(
        audio: ScannedSourceFile,
        among files: [ScannedSourceFile],
        embedded: EmbeddedLyricsPayload?
    ) -> ImportLyricsInspection {
        ImportLyricsResolver().resolve(
            sidecar: lyricsMatcher.match(audio: audio, among: files),
            embedded: embedded
        ) { url in
            try String(contentsOf: url, encoding: .utf8)
        }
    }
}

struct ImportLyricsResolver: Sendable {
    func resolve(
        sidecar: LyricsMatch,
        embedded: EmbeddedLyricsPayload?,
        readSidecar: (URL) throws -> String
    ) -> ImportLyricsInspection {
        switch sidecar {
        case .none:
            return embedded.map(ImportLyricsInspection.embedded)
                ?? .unavailable
        case let .ambiguous(urls):
            return .ambiguous(urls)
        case let .matched(url):
            do {
                let source = try readSidecar(url)
                try LineLevelLRC.validate(source)
                return .linked(url)
            } catch {
                return .malformed(
                    url,
                    reason: error.localizedDescription
                )
            }
        }
    }
}
