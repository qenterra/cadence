@testable import Cadence
import Foundation

enum LibraryResetLifecycleTestError: Error, Sendable {
    case replacementActivationFailed
    case sessionUnavailable
}

@MainActor
final class LibraryResetLocationStore: LibraryLocationStoring {
    private(set) var record: LibraryLocationRecord?

    init(record: LibraryLocationRecord?) {
        self.record = record
    }

    func load() throws -> LibraryLocationRecord? {
        record
    }

    func save(_ record: LibraryLocationRecord?) throws {
        self.record = record
    }
}

@MainActor
private final class LibraryResetBookmarkResolver: LibraryBookmarkResolving {
    private let parentURL: URL

    init(parentURL: URL) {
        self.parentURL = parentURL
    }

    func makeBookmark(for _: URL) throws -> Data {
        Data("reset-bookmark".utf8)
    }

    func resolve(_: Data) throws -> ResolvedLibraryBookmark {
        ResolvedLibraryBookmark(
            parentURL: parentURL,
            isStale: false
        )
    }

    func startAccessing(_: URL) -> Bool {
        true
    }

    func stopAccessing(_: URL) {}
}

@MainActor
struct LibraryResetLifecycleTestContext {
    private struct OriginalPackage {
        let location: ManagedLibraryLocation
        let package: ManagedLibraryPackage
        let identity: LibraryIdentity
        let markerURL: URL
    }

    let directory: URL
    let location: ManagedLibraryLocation
    let package: ManagedLibraryPackage
    let originalIdentity: LibraryIdentity
    let markerURL: URL
    let locationStore: LibraryResetLocationStore
    let libraryBRepository: LibraryRepository
    let libraryBSnapshot: InitialLibrarySnapshot
    let session: LibrarySession
    let model: CadenceAppModel

    static func make() async throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Reset-Lifecycle-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let original = try makeOriginalPackage(in: directory)
        let locationSetup = makeLocationController(
            directory: directory,
            identity: original.identity
        )
        let session = LibrarySession.startup(
            location: original.location,
            locationController: locationSetup.controller
        )
        guard session.store.repository != nil else {
            throw LibraryResetLifecycleTestError.sessionUnavailable
        }
        await session.store.loadInitialLibrary()
        session.availability = .ready

        let libraryB = try LibraryEpochFixture(title: "Library B")
        let libraryBSnapshot = try await makeInitialEpochSnapshot(
            from: libraryB.repository
        )
        let model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .available,
            librarySession: session,
            libraryResetter: ManagedLibraryResetter()
        )
        return Self(
            directory: directory,
            location: original.location,
            package: original.package,
            originalIdentity: original.identity,
            markerURL: original.markerURL,
            locationStore: locationSetup.store,
            libraryBRepository: libraryB.repository,
            libraryBSnapshot: libraryBSnapshot,
            session: session,
            model: model
        )
    }

    private static func makeOriginalPackage(
        in directory: URL
    ) throws -> OriginalPackage {
        let location = ManagedLibraryLocation(musicDirectory: directory)
        let package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        let identity = LibraryIdentity()
        try package.writeIdentity(identity)
        _ = try LibraryContainerFactory.persistentLocal(package: package)
        let markerURL = package.mediaDirectoryURL.appending(
            path: "original.marker"
        )
        try Data("original".utf8).write(to: markerURL)
        return OriginalPackage(
            location: location,
            package: package,
            identity: identity,
            markerURL: markerURL
        )
    }

    private static func makeLocationController(
        directory: URL,
        identity: LibraryIdentity
    ) -> (
        store: LibraryResetLocationStore,
        controller: LibraryLocationController
    ) {
        let store = LibraryResetLocationStore(
            record: LibraryLocationRecord(
                bookmarkData: Data("original-bookmark".utf8),
                identity: identity
            )
        )
        let controller = LibraryLocationController(
            store: store,
            bookmarkResolver: LibraryResetBookmarkResolver(
                parentURL: directory
            )
        )
        return (store, controller)
    }

    func activateLibraryB(
        snapshotLoads: LifecycleInvocationRecorder,
        completions: LifecycleInvocationRecorder
    ) async throws {
        let snapshot = libraryBSnapshot
        try await session.activate(
            repository: libraryBRepository,
            snapshotLoader: { _ in
                await snapshotLoads.record()
                return snapshot
            }
        )
        await completions.record()
    }

    func backupURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix(".Cadence-library-backup-")
        }
    }

    func removeArtifacts() async {
        model.importCoordinator?.cancel()
        model.importCoordinator = nil
        model.importDestination = nil
        model.importRecovery = nil
        try? await session.store.detach()
        await Task.yield()
        var identities = Set([originalIdentity])
        if let currentIdentity = try? package.readIdentity() {
            identities.insert(currentIdentity)
        }
        for identity in identities {
            guard let catalog = try? LocalLibraryCatalogLocation.currentUser(
                identity: identity
            ) else {
                continue
            }
            try? FileManager.default.removeItem(at: catalog.rootURL)
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
