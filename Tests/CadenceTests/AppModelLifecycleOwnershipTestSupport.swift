@testable import Cadence
import Foundation

enum AppModelLifecycleTestError: Error, LocalizedError, Sendable {
    case staleOperation

    var errorDescription: String? {
        "Stale lifecycle operation."
    }
}

@MainActor
struct MetadataRepairLifecycleTestContext {
    let directory: URL
    let libraryBRepository: LibraryRepository
    let session: LibrarySession
    let model: CadenceAppModel

    static func make() async throws -> Self {
        let setup = try await AppModelLifecycleLibrarySetup.make(
            label: "Metadata-Repair"
        )
        return Self(
            directory: setup.directory,
            libraryBRepository: setup.libraryBRepository,
            session: setup.session,
            model: setup.model
        )
    }

    func activateLibraryB() async throws {
        try await session.activate(repository: libraryBRepository)
    }

    func removeDirectory() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
struct ResetReopenLifecycleTestContext {
    let directory: URL
    let location: ManagedLibraryLocation
    let libraryBRepository: LibraryRepository
    let failureCheckpoint = LibraryEpochResultGate(())
    let session: LibrarySession
    let model: CadenceAppModel

    static func make() async throws -> Self {
        let setup = try await AppModelLifecycleLibrarySetup.make(
            label: "Reset-Reopen"
        )
        return Self(
            directory: setup.directory,
            location: setup.location,
            libraryBRepository: setup.libraryBRepository,
            session: setup.session,
            model: setup.model
        )
    }

    func removeDirectory() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private struct AppModelLifecycleLibrarySetup {
    let directory: URL
    let location: ManagedLibraryLocation
    let libraryBRepository: LibraryRepository
    let session: LibrarySession
    let model: CadenceAppModel

    static func make(
        label: String,
        lyricsSearchIndexer: (any LyricsSearchIndexing)? = nil
    ) async throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-\(label)-Lifecycle-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let location = ManagedLibraryLocation(musicDirectory: directory)
        let package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let session = LibrarySession.startup(location: location)
        try await session.store.attach(
            repository: libraryA.repository,
            package: package,
            lyricsSearchIndexer: lyricsSearchIndexer
        )
        await session.store.loadInitialLibrary()
        session.availability = .ready
        let model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .available,
            librarySession: session
        )
        return Self(
            directory: directory,
            location: location,
            libraryBRepository: libraryB.repository,
            session: session,
            model: model
        )
    }
}
