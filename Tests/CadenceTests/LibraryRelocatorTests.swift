@testable import Cadence
import Foundation
import Testing

struct LibraryRelocatorTests {
    @Test("Relocation copies and verifies every file before exposing the destination")
    func verifiedRelocation() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceParent = root.appending(path: "Source", directoryHint: .isDirectory)
        let destinationParent = root.appending(path: "Destination", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceParent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        let source = ManagedLibraryLocation(musicDirectory: sourceParent)
        let package = ManagedLibraryPackage(location: source)
        try package.bootstrapForConfirmedImport()
        try Data("audio".utf8).write(
            to: package.mediaDirectoryURL.appending(path: "track.flac")
        )
        try Data("derived index".utf8).write(
            to: package.lyricsSearchDatabaseURL
        )

        let relocator = LibraryRelocator(
            validate: { _ in try LibraryContainerFactory.inMemory() }
        )
        let prepared = try await relocator.prepare(
            source: source,
            destinationParent: destinationParent
        )

        #expect(prepared.destination.packageURL.lastPathComponent == "Cadence.library")
        #expect(FileManager.default.fileExists(atPath: prepared.destination.packageURL.path))
        #expect(FileManager.default.fileExists(atPath: source.packageURL.path))
        #expect(prepared.manifest.phase == .destinationValidated)
        #expect(!prepared.manifest.files.isEmpty)
        #expect(
            !prepared.manifest.files.contains {
                $0.relativePath.hasPrefix("Metadata/Search.sqlite")
            }
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: ManagedLibraryPackage(
                    location: prepared.destination
                ).lyricsSearchDatabaseURL.path
            )
        )
    }

    @Test("An existing destination is reported and never overwritten")
    func destinationConflict() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceParent = root.appending(path: "Source", directoryHint: .isDirectory)
        let destinationParent = root.appending(path: "Destination", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceParent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        let source = ManagedLibraryLocation(musicDirectory: sourceParent)
        try ManagedLibraryPackage(location: source).bootstrapForConfirmedImport()
        let destination = ManagedLibraryLocation(musicDirectory: destinationParent)
        try ManagedLibraryPackage(location: destination).bootstrapForConfirmedImport()
        let marker = destination.packageURL.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: marker)

        await #expect(throws: LibraryRelocationError.destinationConflict(destination.packageURL)) {
            try await LibraryRelocator().prepare(
                source: source,
                destinationParent: destinationParent
            )
        }
        #expect(try Data(contentsOf: marker) == Data("keep".utf8))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Relocation-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
