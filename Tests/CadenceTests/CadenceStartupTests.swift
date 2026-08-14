@testable import Cadence
import Foundation
import Testing

@MainActor
struct CadenceStartupTests {
    @Test("Empty startup does not report unavailable persistent features")
    func emptyStartupIsQuiet() async throws {
        let musicDirectory = FileManager.default.temporaryDirectory.appending(
            path: "CadenceStartupTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: musicDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: musicDirectory)
        }
        let session = LibrarySession.startup(
            location: ManagedLibraryLocation(
                musicDirectory: musicDirectory
            )
        )
        let model = CadenceAppModel.production(
            librarySession: session
        )

        await model.loadInitialPersistentFeatures()

        #expect(session.availability == .empty)
        #expect(session.store.operationFailure == nil)
        #expect(session.store.playlistListState == .idle)
    }
}
