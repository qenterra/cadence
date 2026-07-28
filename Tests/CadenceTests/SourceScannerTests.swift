@testable import Cadence
import Foundation
import Testing

struct SourceScannerTests {
    @Test("Recursive scan is deterministic and keeps only supported audio and LRC")
    func deterministicSupportedFiles() async throws {
        try await withTemporaryDirectory { root in
            let album = root.appending(
                path: "Album",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: album,
                withIntermediateDirectories: true
            )
            try write("b", to: album.appending(path: "02 Song.MP3"))
            try write("a", to: album.appending(path: "01 Song.flac"))
            try write("lyrics", to: album.appending(path: "01 Song.LRC"))
            try write("ignore", to: album.appending(path: "cover.jpg"))

            let files = try await SourceScanner().scan(
                source: ImportSource(urls: [root])
            )

            #expect(
                files.map(\.relativePath) == [
                    "Album/01 Song.LRC",
                    "Album/01 Song.flac",
                    "Album/02 Song.MP3",
                ]
            )
            #expect(
                files.map(\.kind) == [
                    .lyrics,
                    .audio(.flac),
                    .audio(.mp3),
                ]
            )
        }
    }

    @Test("Scanner skips symlink traversal and nested Cadence libraries")
    func skipsUnsafeDescendants() async throws {
        try await withTemporaryDirectory { root in
            let outside = root.deletingLastPathComponent().appending(
                path: "CadenceScannerOutside-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: outside,
                withIntermediateDirectories: true
            )
            defer {
                try? FileManager.default.removeItem(at: outside)
            }
            try write("outside", to: outside.appending(path: "Escape.flac"))

            let symlink = root.appending(
                path: "Linked",
                directoryHint: .isDirectory
            )
            try FileManager.default.createSymbolicLink(
                at: symlink,
                withDestinationURL: outside
            )

            let nestedPackage = root.appending(
                path: ManagedLibraryLocation.packageFilename,
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: nestedPackage,
                withIntermediateDirectories: true
            )
            try write(
                "managed",
                to: nestedPackage.appending(path: "Managed.flac")
            )
            try write("safe", to: root.appending(path: "Safe.wav"))

            let files = try await SourceScanner().scan(
                source: ImportSource(urls: [root])
            )

            #expect(files.map(\.relativePath) == ["Safe.wav"])
        }
    }

    @Test("A cancelled scan stops before enumerating")
    func cancellation() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SourceScanner().scan(
                source: ImportSource(urls: [])
            )
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    private func write(
        _ text: String,
        to url: URL
    ) throws {
        try Data(text.utf8).write(to: url)
    }

    private func withTemporaryDirectory(
        _ operation: (URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "CadenceScannerTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try await operation(directory)
    }
}
