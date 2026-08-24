@testable import Cadence
import Darwin
import Foundation
import SwiftData
import Testing

extension LocalLibraryCatalogMigrationTests {
    @MainActor
    @Test("A durable package pointer precedes catalog source cleanup")
    func catalogPointerIsDurableBeforePackageCleanup() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "pointer-order")
        let gate = OneShotFailureGate(target: .afterSourceCleanupIntent)
        let migration = LocalLibraryCatalogMigration(
            faultInjector: LocalCatalogMigrationFaultInjector(gate.inject)
        )

        do {
            _ = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory,
                migration: migration,
                openStore: { _ in try LibraryContainerFactory.inMemory() }
            )
            Issue.record("Expected source cleanup to stop at the injected boundary.")
        } catch {
            // The durable state at this boundary is asserted below.
        }

        #expect(gate.didInject)
        #expect(try fixture.manifest().phase == .sourceCleanup)
        #expect(FileManager.default.fileExists(atPath: fixture.package.metadataStoreURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.catalogPointerURL.path))
        if FileManager.default.fileExists(atPath: fixture.catalogPointerURL.path) {
            #expect(try fixture.catalogPointer().libraryID == fixture.identity.id)
        }
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("Losing a migrated local catalog never recreates it over retained media")
    func completedMigrationLossPreservesMediaAndDoesNotRecreateStore() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "retained-media")
        let media = try fixture.writeManagedMedia()
        let identityBytes = try Data(contentsOf: fixture.package.identityURL)

        do {
            let opened = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
            withExtendedLifetime(opened) {}
        }
        let pointerBytes = try? Data(contentsOf: fixture.catalogPointerURL)
        #expect(pointerBytes != nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.package.metadataStoreURL.path))

        try FileManager.default.removeItem(at: fixture.localCatalog.rootURL)
        expectCatalogMigrationError("missingLocalCatalog") {
            _ = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
        }

        #expect(!FileManager.default.fileExists(atPath: fixture.localCatalog.storeURL.path))
        #expect(try Data(contentsOf: fixture.package.identityURL) == identityBytes)
        #expect(try Data(contentsOf: media.url) == media.bytes)
        if let pointerBytes {
            #expect(try Data(contentsOf: fixture.catalogPointerURL) == pointerBytes)
        }
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("Retained managed media rejects attachment when no pointer exists yet")
    func retainedMediaWithoutPointerRejectsExistingAttachment() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let media = try fixture.writeManagedMedia()
        let openEntered = LockedFlag()

        expectCatalogMigrationError("missingLocalCatalog") {
            _ = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory,
                openStore: { _ in
                    openEntered.set()
                    return try LibraryContainerFactory.inMemory()
                }
            )
        }

        #expect(!openEntered.value)
        #expect(try Data(contentsOf: media.url) == media.bytes)
        #expect(!FileManager.default.fileExists(atPath: fixture.localCatalog.storeURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.catalogPointerURL.path))
    }

    @MainActor
    @Test("A confirmed empty bootstrap creates one catalog and records its authority")
    func confirmedEmptyBootstrapCreatesStoreAndRecordsPointer() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }

        do {
            let opened = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
            #expect(FileManager.default.fileExists(atPath: fixture.localCatalog.storeURL.path))
            withExtendedLifetime(opened) {}
        }
        let pointerBytes = try? Data(contentsOf: fixture.catalogPointerURL)
        #expect(pointerBytes != nil)
        if pointerBytes != nil {
            #expect(try fixture.catalogPointer().libraryID == fixture.identity.id)
        }

        try FileManager.default.removeItem(at: fixture.localCatalog.rootURL)
        let openEntered = LockedFlag()
        expectCatalogMigrationError("missingLocalCatalog") {
            _ = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory,
                openStore: { _ in
                    openEntered.set()
                    return try LibraryContainerFactory.inMemory()
                }
            )
        }

        #expect(!openEntered.value)
        #expect(!FileManager.default.fileExists(atPath: fixture.localCatalog.storeURL.path))
        if let pointerBytes {
            #expect(try Data(contentsOf: fixture.catalogPointerURL) == pointerBytes)
        }
    }

    @MainActor
    @Test(
        "Local SQLite sidecars without a main catalog are rejected and preserved",
        arguments: LocalOrphanSidecarSet.allCases
    )
    func localSidecarsWithoutMainAreRejectedAndPreserved(
        _ sidecarSet: LocalOrphanSidecarSet
    ) throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.localCatalog.metadataDirectoryURL,
            withIntermediateDirectories: true
        )
        var expectedBytes: [String: Data] = [:]
        for suffix in sidecarSet.suffixes {
            let bytes = Data("local-orphan\(suffix)".utf8)
            try bytes.write(
                to: URL(filePath: fixture.localCatalog.storeURL.path + suffix)
            )
            expectedBytes[suffix] = bytes
        }
        let openEntered = LockedFlag()

        expectCatalogMigrationError("orphanedLocalSidecars") {
            _ = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory,
                openStore: { _ in
                    openEntered.set()
                    return try LibraryContainerFactory.inMemory()
                }
            )
        }

        #expect(!openEntered.value)
        #expect(!FileManager.default.fileExists(atPath: fixture.localCatalog.storeURL.path))
        for (suffix, bytes) in expectedBytes {
            let sidecar = URL(filePath: fixture.localCatalog.storeURL.path + suffix)
            #expect(try Data(contentsOf: sidecar) == bytes)
        }
    }

    @MainActor
    @Test(
        "An invalid package catalog pointer is preserved and rejected before open",
        arguments: CatalogPointerDamage.allCases
    )
    func invalidCatalogPointerFailsBeforeFactoryOpen(
        _ damage: CatalogPointerDamage
    ) throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let pointerBytes = try damage.bytes(libraryID: fixture.identity.id)
        try pointerBytes.write(to: fixture.catalogPointerURL)
        let openEntered = LockedFlag()

        expectCatalogMigrationError(damage.expectedErrorPrefix) {
            _ = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory,
                openStore: { _ in
                    openEntered.set()
                    return try LibraryContainerFactory.inMemory()
                }
            )
        }

        #expect(!openEntered.value)
        #expect(try Data(contentsOf: fixture.catalogPointerURL) == pointerBytes)
        #expect(!FileManager.default.fileExists(atPath: fixture.localCatalog.storeURL.path))
    }

    @MainActor
    @Test("A valid pre-pointer complete catalog records authority after reopen")
    func completeManifestBackfillsMissingPointerAfterSuccessfulOpen() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "pointer-backfill")
        let migration = LocalLibraryCatalogMigration()
        let candidate = try migration.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        try migration.commit(#require(candidate))
        if FileManager.default.fileExists(atPath: fixture.catalogPointerURL.path) {
            try FileManager.default.removeItem(at: fixture.catalogPointerURL)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.catalogPointerURL.path))

        do {
            let opened = try LibraryContainerFactory.persistentLocal(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
            withExtendedLifetime(opened) {}
        }

        #expect(FileManager.default.fileExists(atPath: fixture.catalogPointerURL.path))
        if FileManager.default.fileExists(atPath: fixture.catalogPointerURL.path) {
            #expect(try fixture.catalogPointer().libraryID == fixture.identity.id)
        }
        #expect(try fixture.manifest().phase == .complete)
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("Partial source cleanup is idempotent")
    func sourceCleanupIsIdempotent() throws {
        let cleanupPoints: [LocalCatalogMigrationFailurePoint] = [
            .afterSourceMainRemoved,
            .afterSourceWALRemoved,
            .afterSourceSHMRemoved,
            .afterSearchMainRemoved,
            .afterSearchWALRemoved,
            .afterSearchSHMRemoved,
        ]
        for point in cleanupPoints {
            let fixture = try MigrationFixture()
            defer { fixture.remove() }
            let sourceContainer = try fixture.makeSourceCatalog(
                marker: "cleanup-\(point.rawValue)"
            )
            try fixture.writeSearchArtifacts()
            let gate = OneShotFailureGate(target: point)
            let interrupted = LocalLibraryCatalogMigration(
                faultInjector: LocalCatalogMigrationFaultInjector(gate.inject)
            )
            do {
                let candidate = try interrupted.prepareIfNeeded(
                    package: fixture.package,
                    applicationSupportDirectory: fixture.applicationSupportDirectory
                )
                try interrupted.commit(#require(candidate))
            } catch CatalogMigrationTestInterruption.injected {}
            #expect(gate.didInject)

            let recovery = LocalLibraryCatalogMigration()
            let retry = try recovery.prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
            try recovery.commit(#require(retry))
            #expect(try fixture.manifest().phase == .complete)
            withExtendedLifetime(sourceContainer) {}
        }
    }

    @MainActor
    @Test("An adopted cleanup manifest can never authorize package deletion")
    func adoptedCleanupManifestPreservesBothCatalogTrees() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(
            marker: "adopted-cleanup-attack"
        )
        let gate = OneShotFailureGate(target: .afterPromoted)
        do {
            _ = try LocalLibraryCatalogMigration(
                faultInjector: LocalCatalogMigrationFaultInjector(gate.inject)
            ).prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
        } catch CatalogMigrationTestInterruption.injected {}
        #expect(gate.didInject)

        let promoted = try fixture.manifest()
        let impossible = LocalCatalogMigrationManifest(
            schemaVersion: promoted.schemaVersion,
            operationID: promoted.operationID,
            libraryID: promoted.libraryID,
            origin: .adoptedValidatedLocal,
            sourceStoreRelativePath: nil,
            stagingDirectoryName: promoted.stagingDirectoryName,
            legacyDirectoryName: nil,
            phase: .sourceCleanup,
            sourceFiles: [],
            stagedSnapshot: promoted.stagedSnapshot
        )
        try fixture.writeManifest(impossible)
        let before = try fixture.treeSnapshot()

        expectInvalidManifest {
            let migration = LocalLibraryCatalogMigration()
            if let prepared = try migration.prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            ) {
                try migration.commit(prepared)
            }
        }

        #expect(try fixture.treeSnapshot() == before)
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test(
        "Semantically impossible manifests fail closed before mutation",
        arguments: SemanticManifestDamage.allCases
    )
    func semanticManifestDamagePreservesEverything(
        _ damage: SemanticManifestDamage
    ) throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: damage.rawValue)
        let gate = OneShotFailureGate(target: .afterValidated)
        do {
            _ = try LocalLibraryCatalogMigration(
                faultInjector: LocalCatalogMigrationFaultInjector(gate.inject)
            ).prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
        } catch CatalogMigrationTestInterruption.injected {}
        #expect(gate.didInject)

        let invalid = try damage.apply(to: fixture.manifest())
        try fixture.writeManifest(invalid)
        let before = try fixture.treeSnapshot()

        expectInvalidManifest {
            _ = try LocalLibraryCatalogMigration().prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
        }

        #expect(try fixture.treeSnapshot() == before)
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("Corrupt and future manifests fail closed without touching material")
    func corruptOrFutureManifestPreservesEverything() throws {
        for manifestKind in ManifestDamage.allCases {
            let fixture = try MigrationFixture()
            defer { fixture.remove() }
            let sourceContainer = try fixture.makeSourceCatalog(
                marker: manifestKind.rawValue
            )
            let gate = OneShotFailureGate(target: .afterMainCopied)
            do {
                _ = try LocalLibraryCatalogMigration(
                    faultInjector: LocalCatalogMigrationFaultInjector(gate.inject)
                ).prepareIfNeeded(
                    package: fixture.package,
                    applicationSupportDirectory: fixture.applicationSupportDirectory
                )
            } catch CatalogMigrationTestInterruption.injected {}

            switch manifestKind {
            case .corrupt:
                try Data("not-json".utf8).write(
                    to: fixture.localCatalog.migrationManifestURL
                )
            case .future:
                let manifest = try fixture.manifest()
                let future = LocalCatalogMigrationManifest(
                    schemaVersion: LocalCatalogMigrationManifest.currentSchemaVersion + 1,
                    operationID: manifest.operationID,
                    libraryID: manifest.libraryID,
                    origin: manifest.origin,
                    sourceStoreRelativePath: manifest.sourceStoreRelativePath,
                    stagingDirectoryName: manifest.stagingDirectoryName,
                    legacyDirectoryName: manifest.legacyDirectoryName,
                    phase: manifest.phase,
                    sourceFiles: manifest.sourceFiles,
                    stagedSnapshot: manifest.stagedSnapshot
                )
                try JSONEncoder().encode(future).write(
                    to: fixture.localCatalog.migrationManifestURL
                )
            }
            let before = try fixture.treeSnapshot()
            #expect(throws: (any Error).self) {
                _ = try LocalLibraryCatalogMigration().prepareIfNeeded(
                    package: fixture.package,
                    applicationSupportDirectory: fixture.applicationSupportDirectory
                )
            }
            #expect(try fixture.treeSnapshot() == before)
            withExtendedLifetime(sourceContainer) {}
        }
    }

    @MainActor
    @Test("Durability barriers precede promotion and source destruction")
    func durabilityOrderPrecedesDestruction() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "durability")
        let recorder = MigrationEventRecorder()
        let live = LocalCatalogDurability.live
        let durability = LocalCatalogDurability(
            syncFile: { url in
                recorder.append("sync-file:\(url.lastPathComponent)")
                try live.syncFile(url)
            },
            syncDirectory: { url in
                recorder.append("sync-directory:\(url.lastPathComponent)")
                try live.syncDirectory(url)
            },
            atomicRename: { source, destination in
                recorder.append(
                    "rename:\(source.lastPathComponent)->\(destination.lastPathComponent)"
                )
                try live.atomicRename(source, destination)
            }
        )
        let migration = LocalLibraryCatalogMigration(
            faultInjector: LocalCatalogMigrationFaultInjector { point in
                recorder.append("fault:\(point.rawValue)")
            },
            durability: durability
        )
        let candidate = try migration.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        try migration.commit(#require(candidate))

        let events = recorder.events
        let validated = try #require(events.firstIndex(of: "fault:afterValidated"))
        let intent = try #require(events.firstIndex(of: "fault:afterPromotionIntent"))
        let rename = try #require(
            events.firstIndex(where: { $0.hasPrefix("rename:.Metadata-") })
        )
        let renamed = try #require(
            events.firstIndex(of: "fault:afterPromotionRename")
        )
        let promoted = try #require(events.firstIndex(of: "fault:afterPromoted"))
        let cleanup = try #require(
            events.firstIndex(of: "fault:afterSourceCleanupIntent")
        )
        let sourceRemoved = try #require(
            events.firstIndex(of: "fault:afterSourceMainRemoved")
        )
        #expect(validated < intent)
        #expect(intent < rename)
        #expect(rename < renamed)
        #expect(renamed < promoted)
        #expect(promoted < cleanup)
        #expect(cleanup < sourceRemoved)
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("Every migration fixture path stays under its temporary root")
    func allFixturePathsStayUnderTemporaryRoot() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "paths")
        _ = try LocalLibraryCatalogMigration().prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )

        let prefix = fixture.root.standardizedFileURL.path + "/"
        for url in try fixture.allDescendants() {
            #expect(url.standardizedFileURL.path.hasPrefix(prefix))
        }
        let manifest = try fixture.manifest()
        #expect(!manifest.stagingDirectoryName.contains("/"))
        #expect(manifest.legacyDirectoryName?.contains("/") != true)
        withExtendedLifetime(sourceContainer) {}
    }
}
