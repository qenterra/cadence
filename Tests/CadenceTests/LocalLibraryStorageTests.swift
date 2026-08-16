@testable import Cadence
import Foundation
import SwiftData
import Testing

struct LocalLibraryStorageTests {
    @MainActor
    @Test("Local library writes catalog changes into the Cadence package")
    func packageIsCanonicalStore() async throws {
        let musicDirectory = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Local-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: musicDirectory) }
        let location = ManagedLibraryLocation(
            musicDirectory: musicDirectory
        )
        let package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        try package.writeIdentity(LibraryIdentity())
        _ = try LibraryContainerFactory.persistent(package: package)
        let session = LibrarySession.startup(location: location)

        _ = try await session.store.createTag(
            displayPath: "Local / Canonical"
        )

        let reopened = try LibraryContainerFactory.persistent(
            package: package
        )
        let context = ModelContext(reopened)
        let tags = try context.fetch(FetchDescriptor<TagRecord>())
        #expect(tags.map(\.displayPath) == ["Local / Canonical"])
    }
}
