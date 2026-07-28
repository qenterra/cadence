@testable import Cadence
import Foundation

struct SuccessfulImportContext {
    let fixture: ImportFixture
    let candidate: ImportInspectionCandidate
    let completion: ManagedImportCompletion
    let audioData: Data
    let lyricData: Data
    let audioURL: URL
    let lyricURL: URL
    let destination: ManagedLibraryImportDestination
}

struct RecoveryResultContext {
    let result: ManagedImportRecoveryResult
    let point: ManagedImportFailurePoint
    let manifest: ManagedImportManifest
    let candidate: ImportInspectionCandidate
    let destination: ManagedLibraryImportDestination
    let fixture: ImportFixture
}

enum InjectedImportFailure: Error {
    case crash
}

struct ImportFixture {
    let rootURL: URL
    let sourceURL: URL
    let package: ManagedLibraryPackage

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "CadenceImportTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        sourceURL = rootURL.appending(
            path: "Source",
            directoryHint: .isDirectory
        )
        let musicURL = rootURL.appending(
            path: "Music",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: sourceURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: musicURL,
            withIntermediateDirectories: true
        )
        package = ManagedLibraryPackage(
            location: ManagedLibraryLocation(musicDirectory: musicURL)
        )
    }

    func writeSource(
        name: String,
        data: Data
    ) throws -> URL {
        let url = sourceURL.appending(
            path: name,
            directoryHint: .notDirectory
        )
        try data.write(to: url)
        return url
    }

    func candidate(
        audioURL: URL,
        lyricURL: URL? = nil
    ) async throws -> ImportInspectionCandidate {
        let data = try Data(contentsOf: audioURL)
        let hash = try await ContentHasher().sha256(of: audioURL)
        return ImportInspectionCandidate(
            id: UUID(),
            sourceFile: ScannedSourceFile(
                url: audioURL,
                relativePath: audioURL.lastPathComponent,
                kind: .audio(.flac)
            ),
            sizeInBytes: Int64(data.count),
            metadata: ScannedAudioMetadata(
                title: audioURL.deletingPathExtension().lastPathComponent,
                artist: "North Assembly",
                album: "Signals",
                year: 2026,
                trackNumber: 1,
                discNumber: 1,
                duration: 180,
                codec: "FLAC",
                container: "FLAC",
                sampleRate: 48000,
                channelCount: 2,
                bitrate: nil,
                bitDepth: 24,
                spatialFormat: .stereo
            ),
            contentHash: hash,
            lyrics: lyricURL.map(ImportLyricsInspection.linked)
                ?? .unavailable,
            failure: nil,
            duplicateDisposition: .unique
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
