@testable import Cadence
import Foundation
import SwiftData
import Testing

@MainActor
struct LibraryRecoveryTests {
    @Test("Finishing a reset removes the original local catalog")
    func resetFinishRemovesOriginalLocalCatalog() async throws {
        let musicDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "CadenceResetFinishTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: musicDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: musicDirectory) }

        let location = ManagedLibraryLocation(musicDirectory: musicDirectory)
        let package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        let originalIdentity = LibraryIdentity()
        try package.writeIdentity(originalIdentity)
        let originalCatalog = try LocalLibraryCatalogLocation.currentUser(
            identity: originalIdentity
        )
        defer { try? FileManager.default.removeItem(at: originalCatalog.rootURL) }
        _ = try LibraryContainerFactory.persistentLocal(package: package)

        let resetter = ManagedLibraryResetter()
        let prepared = try await resetter.prepare(location: location)
        let replacementCatalog = try LocalLibraryCatalogLocation.currentUser(
            identity: prepared.identity
        )
        defer { try? FileManager.default.removeItem(at: replacementCatalog.rootURL) }

        #expect(FileManager.default.fileExists(atPath: originalCatalog.storeURL.path))
        #expect(await resetter.finish(prepared))
        #expect(!FileManager.default.fileExists(atPath: originalCatalog.rootURL.path))
        #expect(FileManager.default.fileExists(atPath: replacementCatalog.storeURL.path))
    }

    @Test("Reset prepares a verified empty library and can restore the original package")
    func resetPreparationAndRollback() async throws {
        let musicDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "CadenceResetTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: musicDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: musicDirectory) }

        let location = ManagedLibraryLocation(musicDirectory: musicDirectory)
        let package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        let originalIdentity = LibraryIdentity()
        try package.writeIdentity(originalIdentity)
        _ = try LibraryContainerFactory.persistent(package: package)
        let markerURL = package.mediaDirectoryURL.appending(path: "original.marker")
        try Data("original".utf8).write(to: markerURL)

        let resetter = ManagedLibraryResetter()
        let prepared = try await resetter.prepare(location: location)

        #expect(prepared.identity != originalIdentity)
        #expect(try package.readIdentity() == prepared.identity)
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))
        #expect(FileManager.default.fileExists(atPath: prepared.backupURL.path))
        var replacementContainer: ModelContainer? = try LibraryContainerFactory.persistent(
            package: package
        )
        var replacementRepository: LibraryRepository? = try LibraryRepository(
            modelContainer: #require(replacementContainer)
        )
        #expect(try await replacementRepository?.catalogCounts() == .empty)
        replacementRepository = nil
        replacementContainer = nil

        let restored = try await resetter.rollback(prepared)

        #expect(restored)
        #expect(try package.readIdentity() == originalIdentity)
        #expect(FileManager.default.fileExists(atPath: markerURL.path))
    }

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
        let identity = LibraryIdentity()
        try package.writeIdentity(identity)
        let localCatalog = try LocalLibraryCatalogLocation.currentUser(
            identity: identity
        )
        defer { try? FileManager.default.removeItem(at: localCatalog.rootURL) }
        let session = LibrarySession.startup(location: location)
        guard case let .failed(failure) = session.availability else {
            Issue.record("Expected missing metadata failure.")
            return
        }
        #expect(failure.kind == .missingMetadataStore)
        #expect(failure.revealURL == localCatalog.rootURL)

        _ = try LibraryContainerFactory.persistent(package: package)
        try package.writeIdentity(LibraryIdentity())
        let model = CadenceAppModel.production(librarySession: session)
        await model.retryManagedLibrary()

        #expect(model.librarySession.availability == .ready)
    }
}
