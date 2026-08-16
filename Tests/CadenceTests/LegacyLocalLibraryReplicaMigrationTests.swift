@testable import Cadence
import Foundation
import Testing

struct LegacyLocalLibraryReplicaMigrationTests {
    @Test("Legacy Application Support replica is promoted into the local package")
    func promotesLegacyReplica() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let migration = LegacyLocalLibraryReplicaMigration()

        let candidate = try migration.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        let prepared = try #require(candidate)
        #expect(
            try Data(contentsOf: fixture.package.metadataStoreURL)
                == Data("replica".utf8)
        )

        try migration.commit(prepared)

        #expect(!FileManager.default.fileExists(atPath: fixture.legacy.rootURL.path))
        #expect(
            try migration.prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            ) == nil
        )
    }

    @Test("Failed replica promotion can restore the previous package store")
    func rollbackRestoresPackage() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let migration = LegacyLocalLibraryReplicaMigration()
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
    }
}

private struct Fixture {
    let root: URL
    let applicationSupportDirectory: URL
    let package: ManagedLibraryPackage
    let legacy: LegacyLocalLibraryReplicaLocation

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
        let legacy = LegacyLocalLibraryReplicaLocation(
            applicationSupportDirectory: applicationSupportDirectory,
            identity: identity
        )
        try FileManager.default.createDirectory(
            at: legacy.storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("replica".utf8).write(to: legacy.storeURL)
        self.root = root
        self.applicationSupportDirectory = applicationSupportDirectory
        self.package = package
        self.legacy = legacy
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
