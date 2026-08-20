@testable import Cadence
import Foundation
import Testing

struct LocalLibraryCatalogMigrationTests {
    @Test("Package catalog is promoted into Application Support")
    func promotesPackageCatalog() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let migration = LocalLibraryCatalogMigration()

        let candidate = try migration.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        let prepared = try #require(candidate)
        #expect(
            try Data(contentsOf: fixture.localCatalog.storeURL)
                == Data("package".utf8)
        )

        try migration.commit(prepared)

        #expect(FileManager.default.fileExists(atPath: fixture.localCatalog.storeURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.package.metadataStoreURL.path))
        #expect(
            try migration.prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            ) == nil
        )
    }

    @Test("Failed local catalog promotion restores the package store")
    func rollbackRestoresPackageCatalog() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let migration = LocalLibraryCatalogMigration()
        let candidate = try migration.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        let prepared = try #require(candidate)

        try migration.rollback(prepared)

        #expect(
            try Data(contentsOf: fixture.package.metadataStoreURL)
                == Data("package".utf8)
        )
        #expect(!FileManager.default.fileExists(atPath: fixture.localCatalog.rootURL.path))
    }
}

private struct Fixture {
    let root: URL
    let applicationSupportDirectory: URL
    let package: ManagedLibraryPackage
    let localCatalog: LocalLibraryCatalogLocation

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Replica-Migration-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let applicationSupportDirectory = root.appending(
            path: "Application Support",
            directoryHint: .isDirectory
        )
        let package = ManagedLibraryPackage(
            location: ManagedLibraryLocation(
                musicDirectory: root.appending(
                    path: "Music",
                    directoryHint: .isDirectory
                )
            )
        )
        try package.bootstrapForConfirmedImport()
        let identity = LibraryIdentity()
        try package.writeIdentity(identity)
        try Data("package".utf8).write(to: package.metadataStoreURL)
        let localCatalog = LocalLibraryCatalogLocation(
            applicationSupportDirectory: applicationSupportDirectory,
            identity: identity
        )
        self.root = root
        self.applicationSupportDirectory = applicationSupportDirectory
        self.package = package
        self.localCatalog = localCatalog
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
