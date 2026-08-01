@testable import Cadence
import Foundation
import Testing

@MainActor
struct LibraryRecoveryTests {
    @Test("Retry reopens a repaired managed library")
    func retryReopensRepairedLibrary() async throws {
        let musicDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "CadenceRecoveryTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: musicDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: musicDirectory)
        }

        let location = ManagedLibraryLocation(
            musicDirectory: musicDirectory
        )
        let package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        let session = LibrarySession.startup(location: location)
        guard case let .failed(failure) = session.availability else {
            Issue.record("Expected missing metadata failure.")
            return
        }
        #expect(failure.kind == .missingMetadataStore)
        #expect(failure.revealURL == location.packageURL)

        _ = try LibraryContainerFactory.persistent(package: package)
        let model = CadenceAppModel.production(librarySession: session)
        await model.retryManagedLibrary()

        #expect(model.librarySession.availability == .ready)
    }
}
