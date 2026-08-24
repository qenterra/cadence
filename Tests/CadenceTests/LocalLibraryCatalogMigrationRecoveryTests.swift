@testable import Cadence
import Darwin
import Foundation
import SwiftData
import Testing

extension LocalLibraryCatalogMigrationTests {
    @MainActor
    @Test("SwiftData open failure rolls back only the owned promoted catalog")
    func swiftDataOpenFailurePreservesRollbackSource() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "open-failure")

        #expect(throws: CatalogMigrationTestInterruption.self) {
            _ = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory,
                openStore: { _ in
                    throw CatalogMigrationTestInterruption.injected
                }
            )
        }

        #expect(
            FileManager.default.fileExists(
                atPath: fixture.package.metadataStoreURL.path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.localCatalog.metadataDirectoryURL.path
            )
        )
        #expect(try fixture.manifest().phase == .prepared)
        let retry = try LocalLibraryCatalogMigration().prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        #expect(retry != nil)
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("A competing factory open cannot roll back the owner's transaction")
    func concurrentFactoryOpenCannotRollbackOwner() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "factory-race")
        let race = FactoryOpenRace()
        defer { race.releaseOwner.signal() }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try LibraryContainerFactory.persistentLocal(
                    package: fixture.package,
                    applicationSupportDirectory: fixture.applicationSupportDirectory,
                    openStore: { _ in
                        let container = try LibraryContainerFactory.inMemory()
                        race.ownerOpened.signal()
                        guard race.releaseOwner.wait(timeout: .now() + 10) == .success else {
                            throw CatalogMigrationTestInterruption.injected
                        }
                        return container
                    }
                )
            } catch {
                race.recordOwnerFailure(error)
            }
            race.ownerFinished.signal()
        }

        try #require(race.ownerOpened.wait(timeout: .now() + 10) == .success)
        #expect(throws: (any Error).self) {
            _ = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory,
                openStore: { _ in
                    race.recordCompetingOpen()
                    throw CatalogMigrationTestInterruption.injected
                }
            )
        }
        #expect(!race.didEnterCompetingOpen)
        #expect(FileManager.default.fileExists(atPath: fixture.package.metadataStoreURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.localCatalog.storeURL.path))

        race.releaseOwner.signal()
        try #require(race.ownerFinished.wait(timeout: .now() + 10) == .success)
        #expect(race.ownerFailure == nil)
        #expect(try fixture.manifest().phase == .complete)
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("An external lock owner blocks the factory and process death releases it")
    func externalLockOwnerDeathReleasesFactoryTransaction() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "external-lock")
        try FileManager.default.createDirectory(
            at: fixture.localCatalog.rootURL,
            withIntermediateDirectories: true
        )
        let lockURL = fixture.localCatalog.rootURL.appending(
            path: "CatalogTransaction.lock",
            directoryHint: .notDirectory
        )
        let owner = try startExternalCatalogLockOwner(at: lockURL)
        defer {
            if owner.isRunning {
                owner.terminateAndWait()
            }
        }
        let competingOpen = LockedFlag()

        #expect(throws: (any Error).self) {
            _ = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory,
                openStore: { _ in
                    competingOpen.set()
                    throw CatalogMigrationTestInterruption.injected
                }
            )
        }
        #expect(!competingOpen.value)
        #expect(FileManager.default.fileExists(atPath: fixture.package.metadataStoreURL.path))

        owner.terminateAndWait()
        _ = try LibraryContainerFactory.persistentLocal(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory,
            openStore: { _ in try LibraryContainerFactory.inMemory() }
        )
        #expect(try fixture.manifest().phase == .complete)
        withExtendedLifetime(sourceContainer) {}
    }

    @Test("Promotion rename never replaces an existing directory entry")
    func promotionRenameIsExclusive() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Catalog-Rename-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "source", directoryHint: .isDirectory)
        let destination = root.appending(path: "destination", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: destination,
            withDestinationURL: root.appending(path: "missing-target")
        )

        #expect(throws: (any Error).self) {
            try LocalCatalogDurability.live.atomicRename(source, destination)
        }
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(
            try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
                .isSymbolicLink == true
        )
    }

    @MainActor
    @Test("A durability failure after final removal resumes rollback on restart")
    func rollbackAfterFinalRemovalIsRestartable() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "rollback-sync")
        let gate = AfterDirectorySyncFailureGate(
            target: fixture.localCatalog.rootURL,
            matchesToSkip: 1
        )
        let live = LocalCatalogDurability.live
        let migration = LocalLibraryCatalogMigration(
            durability: LocalCatalogDurability(
                syncFile: live.syncFile,
                syncDirectory: { url in
                    try live.syncDirectory(url)
                    try gate.injectIfArmed(for: url)
                },
                atomicRename: live.atomicRename
            )
        )
        let candidate = try migration.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        let prepared = try #require(candidate)
        gate.arm()

        #expect(throws: CatalogMigrationTestInterruption.self) {
            try migration.rollback(prepared)
        }
        #expect(gate.didInject)
        #expect(FileManager.default.fileExists(atPath: fixture.package.metadataStoreURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.localCatalog.storeURL.path))

        let recovery = LocalLibraryCatalogMigration()
        let retry = try recovery.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        try recovery.commit(#require(retry))
        #expect(try fixture.manifest().phase == .complete)
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test(
        "Rollback converges from every durable boundary",
        arguments: RollbackCrashScenario.allCases
    )
    func rollbackBoundaryConverges(
        _ scenario: RollbackCrashScenario
    ) throws {
        let faultPoint = LocalCatalogMigrationFailurePoint(
            rawValue: scenario.boundary.rawValue
        )
        #expect(faultPoint != nil)
        guard let faultPoint else {
            return
        }

        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(
            marker: "rollback-\(scenario.boundary.rawValue)-\(scenario.preservesLegacy)"
        )
        if scenario.preservesLegacy {
            _ = try fixture.writeStaleLocalMetadata()
        }
        let gate = OneShotFailureGate(target: faultPoint)
        let migration = LocalLibraryCatalogMigration(
            faultInjector: LocalCatalogMigrationFaultInjector(gate.inject)
        )
        let candidate = try migration.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        let prepared = try #require(candidate)

        #expect(throws: CatalogMigrationTestInterruption.self) {
            try migration.rollback(prepared)
        }
        #expect(gate.didInject)
        #expect(FileManager.default.fileExists(atPath: fixture.package.metadataStoreURL.path))

        let recovery = LocalLibraryCatalogMigration()
        let retry = try recovery.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        try recovery.commit(#require(retry))
        #expect(try fixture.manifest().phase == .complete)
        #expect(try fixture.operationDirectories().isEmpty)
        if scenario.preservesLegacy {
            let legacyName = try #require(fixture.manifest().legacyDirectoryName)
            #expect(
                FileManager.default.fileExists(
                    atPath: fixture.localCatalog.rootURL
                        .appending(path: legacyName)
                        .appending(path: "Library.store")
                        .path
                )
            )
        }
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("A redirected completed catalog member is rejected before SQLite opens")
    func completedStoreSymlinkIsRejected() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "store-containment")
        let migration = LocalLibraryCatalogMigration()
        let candidate = try migration.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        try migration.commit(#require(candidate))

        let externalStore = fixture.root.appending(path: "External-Library.store")
        try FileManager.default.copyItem(
            at: fixture.localCatalog.storeURL,
            to: externalStore
        )
        try FileManager.default.removeItem(at: fixture.localCatalog.storeURL)
        try FileManager.default.createSymbolicLink(
            at: fixture.localCatalog.storeURL,
            withDestinationURL: externalStore
        )
        let externalBytes = try Data(contentsOf: externalStore)

        expectUnsafePath {
            _ = try LocalLibraryCatalogMigration().prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
        }
        #expect(try Data(contentsOf: externalStore) == externalBytes)
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("A redirected migration manifest is rejected before it is decoded")
    func manifestSymlinkIsRejected() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "manifest-containment")
        _ = try LocalLibraryCatalogMigration().prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        let externalManifest = fixture.root.appending(path: "External-Manifest.json")
        try FileManager.default.moveItem(
            at: fixture.localCatalog.migrationManifestURL,
            to: externalManifest
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.localCatalog.migrationManifestURL,
            withDestinationURL: externalManifest
        )
        let externalBytes = try Data(contentsOf: externalManifest)

        expectUnsafePath {
            _ = try LocalLibraryCatalogMigration().prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
        }
        #expect(try Data(contentsOf: externalManifest) == externalBytes)
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test(
        "Redirected completed SQLite sidecars are rejected",
        arguments: ["-wal", "-shm"]
    )
    func completedSidecarSymlinkIsRejected(_ suffix: String) throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "sidecar-containment")
        let migration = LocalLibraryCatalogMigration()
        let candidate = try migration.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        try migration.commit(#require(candidate))

        let externalSidecar = fixture.root.appending(
            path: "External-Sidecar\(suffix)"
        )
        try Data("external-sidecar".utf8).write(to: externalSidecar)
        let localSidecar = URL(filePath: fixture.localCatalog.storeURL.path + suffix)
        try FileManager.default.createSymbolicLink(
            at: localSidecar,
            withDestinationURL: externalSidecar
        )
        let externalBytes = try Data(contentsOf: externalSidecar)

        expectUnsafePath {
            _ = try LocalLibraryCatalogMigration().prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
        }
        #expect(try Data(contentsOf: externalSidecar) == externalBytes)
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test(
        "Local catalog ancestor redirection cannot leave Application Support",
        arguments: LocalAncestorRedirect.allCases
    )
    func localAncestorSymlinkIsRejected(
        _ redirect: LocalAncestorRedirect
    ) throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(
            marker: "ancestor-\(redirect.rawValue)"
        )
        try FileManager.default.createDirectory(
            at: fixture.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        let externalRoot = fixture.root.appending(
            path: "External-\(redirect.rawValue)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: externalRoot,
            withIntermediateDirectories: true
        )
        try redirect.install(in: fixture, destination: externalRoot)
        let externalBefore = try snapshotTree(at: externalRoot)
        let openEntered = LockedFlag()

        expectUnsafePath {
            _ = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory,
                openStore: { _ in
                    openEntered.set()
                    throw CatalogMigrationTestInterruption.injected
                }
            )
        }

        #expect(!openEntered.value)
        #expect(try snapshotTree(at: externalRoot) == externalBefore)
        #expect(FileManager.default.fileExists(atPath: fixture.package.metadataStoreURL.path))
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("A redirected package Metadata directory is rejected before identity read")
    func packageMetadataSymlinkIsRejected() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "package-containment")
        let externalMetadata = fixture.root.appending(
            path: "External-Package-Metadata",
            directoryHint: .isDirectory
        )
        try FileManager.default.moveItem(
            at: fixture.package.metadataDirectoryURL,
            to: externalMetadata
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.package.metadataDirectoryURL,
            withDestinationURL: externalMetadata
        )
        let externalBefore = try snapshotTree(at: externalMetadata)

        expectUnsafePath {
            _ = try LocalLibraryCatalogMigration().prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
        }

        #expect(try snapshotTree(at: externalMetadata) == externalBefore)
        #expect(!FileManager.default.fileExists(atPath: fixture.localCatalog.rootURL.path))
        withExtendedLifetime(sourceContainer) {}
    }
}
