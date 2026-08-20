@testable import Cadence
import Foundation
import SwiftData
import Testing

struct LocalLibraryStorageTests {
    @MainActor
    @Test("Local library writes catalog changes into Application Support")
    func applicationSupportIsCanonicalStore() async throws {
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
        let identity = LibraryIdentity()
        try package.writeIdentity(identity)
        let localCatalog = try LocalLibraryCatalogLocation.currentUser(
            identity: identity
        )
        defer { try? FileManager.default.removeItem(at: localCatalog.rootURL) }
        _ = try LibraryContainerFactory.persistent(package: package)
        let session = LibrarySession.startup(location: location)

        _ = try await session.store.createTag(
            displayPath: "Local / Canonical"
        )

        let reopened = try LibraryContainerFactory.persistentLocal(
            package: package
        )
        let context = ModelContext(reopened)
        let tags = try context.fetch(FetchDescriptor<TagRecord>())
        #expect(tags.map(\.displayPath) == ["Local / Canonical"])
        #expect(FileManager.default.fileExists(atPath: localCatalog.storeURL.path))
        #expect(!FileManager.default.fileExists(atPath: package.metadataStoreURL.path))
    }
}
