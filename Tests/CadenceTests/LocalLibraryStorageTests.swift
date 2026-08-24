@testable import Cadence
import Foundation
import SwiftData
import Testing

struct LocalLibraryStorageTests {
    @MainActor
    @Test("Local library writes catalog changes into Application Support")
    func applicationSupportIsCanonicalStore() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Local-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let musicDirectory = root.appending(
            path: "Managed",
            directoryHint: .isDirectory
        )
        let applicationSupportDirectory = root.appending(
            path: "Application Support",
            directoryHint: .isDirectory
        )
        let location = ManagedLibraryLocation(
            musicDirectory: musicDirectory
        )
        let package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        let identity = LibraryIdentity()
        try package.writeIdentity(identity)
        let localCatalog = LocalLibraryCatalogLocation(
            applicationSupportDirectory: applicationSupportDirectory,
            identity: identity
        )
        let source = try LibraryContainerFactory.persistent(package: package)
        let sourceContext = ModelContext(source)
        sourceContext.insert(TagRecord(displayPath: "Local / Canonical"))
        try sourceContext.save()

        let reopened = try LibraryContainerFactory.persistentLocal(
            package: package,
            applicationSupportDirectory: applicationSupportDirectory
        )
        let context = ModelContext(reopened)
        let tags = try context.fetch(FetchDescriptor<TagRecord>())
        #expect(tags.map(\.displayPath) == ["Local / Canonical"])
        #expect(FileManager.default.fileExists(atPath: localCatalog.storeURL.path))
        #expect(!FileManager.default.fileExists(atPath: package.metadataStoreURL.path))
        withExtendedLifetime(source) {}
    }
}
