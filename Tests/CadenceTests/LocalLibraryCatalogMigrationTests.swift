@testable import Cadence
import Darwin
import Foundation
import SwiftData
import Testing

struct LocalLibraryCatalogMigrationTests {
    @MainActor
    @Test("An existing destination main never proves migration completion")
    func destinationMainDoesNotProveMigration() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(
            marker: "authoritative-package"
        )

        try FileManager.default.createDirectory(
            at: fixture.localCatalog.metadataDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data("stale-partial-destination".utf8).write(
            to: fixture.localCatalog.storeURL
        )

        let prepared = try LocalLibraryCatalogMigration().prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )

        #expect(prepared != nil)
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.localCatalog.storeURL.path
            )
        )
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("Rows committed in WAL become part of the self-contained local main")
    func walCommittedRowsSurviveMigration() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "wal-marker")
        let sourceWAL = URL(filePath: fixture.package.metadataStoreURL.path + "-wal")
        #expect(FileManager.default.fileExists(atPath: sourceWAL.path))

        let candidate = try LocalLibraryCatalogMigration().prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        let prepared = try #require(candidate)

        let finalWAL = URL(filePath: fixture.localCatalog.storeURL.path + "-wal")
        let finalSHM = URL(filePath: fixture.localCatalog.storeURL.path + "-shm")
        #expect(!FileManager.default.fileExists(atPath: finalWAL.path))
        #expect(!FileManager.default.fileExists(atPath: finalSHM.path))

        let probe = try fixture.makeProbePackage(from: fixture.localCatalog.storeURL)
        let probeContainer = try LibraryContainerFactory.persistent(package: probe)
        let tags = try ModelContext(probeContainer).fetch(FetchDescriptor<TagRecord>())
        #expect(tags.map(\.displayPath) == ["wal-marker"])

        _ = prepared
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("Package SHM is recorded for rebuild and is never promoted")
    func shmIsRebuiltNotPromoted() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "shm-marker")
        let sourceSHM = URL(filePath: fixture.package.metadataStoreURL.path + "-shm")
        let staleSHM = Data("stale-shm-must-not-be-promoted".utf8)
        try staleSHM.write(to: sourceSHM)

        let candidate = try LocalLibraryCatalogMigration().prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        _ = try #require(candidate)

        let manifest = try fixture.manifest()
        let shm = try #require(
            manifest.sourceFiles.first(where: { $0.role == .shm })
        )
        #expect(shm.disposition == .rebuild)
        let finalSHM = URL(filePath: fixture.localCatalog.storeURL.path + "-shm")
        #expect(!FileManager.default.fileExists(atPath: finalSHM.path))
        #expect(
            try Data(contentsOf: fixture.localCatalog.storeURL) != staleSHM
        )
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test(
        "Every durable failure point converges after restart",
        arguments: LocalCatalogMigrationFailurePoint.allCases.filter {
            !$0.rawValue.lowercased().contains("rollback")
        }
    )
    func restartAtEveryFailurePointConverges(
        _ failurePoint: LocalCatalogMigrationFailurePoint
    ) throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(
            marker: "restart-\(failurePoint.rawValue)"
        )
        if failurePoint == .afterLegacyMoveIntent
            || failurePoint == .afterLegacyMoveRename {
            _ = try fixture.writeStaleLocalMetadata()
        }
        try fixture.writeSearchArtifacts()
        let gate = OneShotFailureGate(target: failurePoint)
        let interrupted = LocalLibraryCatalogMigration(
            faultInjector: LocalCatalogMigrationFaultInjector(gate.inject)
        )

        do {
            if let prepared = try interrupted.prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            ) {
                try interrupted.commit(prepared)
            }
        } catch CatalogMigrationTestInterruption.injected {
            // The next process instance must recover from this exact boundary.
        }
        #expect(gate.didInject)

        let recovery = LocalLibraryCatalogMigration()
        if let prepared = try recovery.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        ) {
            try recovery.commit(prepared)
        }

        #expect(try fixture.manifest().phase == .complete)
        #expect(try fixture.operationDirectories().isEmpty)
        let probe = try fixture.makeProbePackage(from: fixture.localCatalog.storeURL)
        let probeContainer = try LibraryContainerFactory.persistent(package: probe)
        let tags = try ModelContext(probeContainer).fetch(FetchDescriptor<TagRecord>())
        #expect(tags.map(\.displayPath) == ["restart-\(failurePoint.rawValue)"])
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test(
        "Legacy preservation converges before and after its rename",
        arguments: [
            LocalCatalogMigrationFailurePoint.afterLegacyMoveIntent,
            .afterLegacyMoveRename,
        ]
    )
    func legacyMoveIntentRecovers(
        _ failurePoint: LocalCatalogMigrationFailurePoint
    ) throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "legacy-recovery")
        let staleBytes = try fixture.writeStaleLocalMetadata()
        let gate = OneShotFailureGate(target: failurePoint)
        do {
            _ = try LocalLibraryCatalogMigration(
                faultInjector: LocalCatalogMigrationFaultInjector(gate.inject)
            ).prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
        } catch CatalogMigrationTestInterruption.injected {}
        #expect(gate.didInject)

        let recovery = LocalLibraryCatalogMigration()
        let candidate = try recovery.prepareIfNeeded(
            package: fixture.package,
            applicationSupportDirectory: fixture.applicationSupportDirectory
        )
        try recovery.commit(#require(candidate))

        let manifest = try fixture.manifest()
        let legacyName = try #require(manifest.legacyDirectoryName)
        let legacyStore = fixture.localCatalog.rootURL
            .appending(path: legacyName, directoryHint: .isDirectory)
            .appending(path: "Library.store", directoryHint: .notDirectory)
        #expect(try Data(contentsOf: legacyStore) == staleBytes)
        #expect(manifest.phase == .complete)
        withExtendedLifetime(sourceContainer) {}
    }

    @MainActor
    @Test("Crash after rename accepts only the validated promoted bytes")
    func crashAfterRenameRecognizesOnlyMatchingPromotion() throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let sourceContainer = try fixture.makeSourceCatalog(marker: "rename-marker")
        let gate = OneShotFailureGate(target: .afterPromotionRename)
        let interrupted = LocalLibraryCatalogMigration(
            faultInjector: LocalCatalogMigrationFaultInjector(gate.inject)
        )
        do {
            _ = try interrupted.prepareIfNeeded(
                package: fixture.package,
                applicationSupportDirectory: fixture.applicationSupportDirectory
            )
        } catch CatalogMigrationTestInterruption.injected {}
        #expect(gate.didInject)

        var mismatched = try Data(contentsOf: fixture.localCatalog.storeURL)
        mismatched.append(Data("tampered".utf8))
        try mismatched.write(to: fixture.localCatalog.storeURL)
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
