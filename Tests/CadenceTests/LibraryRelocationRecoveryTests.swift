@testable import Cadence
import Foundation
import Testing

struct LibraryRelocationRecoveryTests {
    @Test("Recovery keeps the active library available when old-folder cleanup is denied")
    func cleanupPermissionFailureIsNonfatal() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Relocation-Recovery-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceParent = root.appending(
            path: "Source",
            directoryHint: .isDirectory
        )
        let destinationParent = root.appending(
            path: "Destination",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: sourceParent,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destinationParent,
            withIntermediateDirectories: true
        )
        let source = ManagedLibraryLocation(musicDirectory: sourceParent)
        let package = ManagedLibraryPackage(location: source)
        try package.bootstrapForConfirmedImport()
        try package.writeIdentity(LibraryIdentity())
        try Data("audio".utf8).write(
            to: package.mediaDirectoryURL.appending(path: "track.flac")
        )
        let prepared = try await LibraryRelocator(
            validate: { _ in try LibraryContainerFactory.inMemory() }
        ).prepare(
            source: source,
            destinationParent: destinationParent
        )

        try await LibraryRelocationRecovery(
            fileManager: PermissionDeniedTrashFileManager()
        ).recover(activeLocation: prepared.destination)

        #expect(
            FileManager.default.fileExists(
                atPath: prepared.destination.packageURL.path
            )
        )
        #expect(FileManager.default.fileExists(atPath: source.packageURL.path))
        #expect(
            FileManager.default.fileExists(
                atPath: prepared.destinationManifestURL.path
            )
        )
    }
}

private final class PermissionDeniedTrashFileManager: FileManager, @unchecked Sendable {
    override func trashItem(
        at _: URL,
        resultingItemURL _: AutoreleasingUnsafeMutablePointer<NSURL?>?
    ) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}
