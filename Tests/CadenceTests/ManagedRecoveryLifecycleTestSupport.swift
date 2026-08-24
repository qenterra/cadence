@testable import Cadence
import Foundation

@MainActor
struct ManagedRecoveryLifecycleTestContext {
    let directory: URL
    let libraryBRepository: LibraryRepository
    let checkpoint: LibraryEpochResultGate<Void>
    let artworkInvocations: LifecycleInvocationRecorder
    let session: LibrarySession
    let model: CadenceAppModel

    static func make(
        suspendingAt checkpointPhase: ManagedRecoveryCheckpointPhase
    ) throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Recovery-Lifecycle-\(UUID().uuidString)",
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
        let destination = ManagedLibraryImportDestination(
            package: package,
            repository: libraryA.repository
        )
        let session = LibrarySession.startup(location: location)
        session.availability = .recovering
        let checkpoint = LibraryEpochResultGate(())
        let artworkInvocations = LifecycleInvocationRecorder()
        let model = makeModel(
            session: session,
            destination: destination,
            checkpoint: checkpoint,
            checkpointPhase: checkpointPhase,
            artworkInvocations: artworkInvocations
        )
        return Self(
            directory: directory,
            libraryBRepository: libraryB.repository,
            checkpoint: checkpoint,
            artworkInvocations: artworkInvocations,
            session: session,
            model: model
        )
    }

    private static func makeModel(
        session: LibrarySession,
        destination: ManagedLibraryImportDestination,
        checkpoint: LibraryEpochResultGate<Void>,
        checkpointPhase: ManagedRecoveryCheckpointPhase,
        artworkInvocations: LifecycleInvocationRecorder
    ) -> CadenceAppModel {
        let effect = ManagedArtworkPublicationEffect(
            ownerKind: .artist,
            ownerID: UUID(),
            previousArtworkID: nil,
            newArtworkID: UUID()
        )
        return CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .available,
            librarySession: session,
            importDestination: destination,
            importRecovery: ManagedLibraryImportRecovery(
                destination: destination
            ),
            managedArtworkRecoveryOperation: { _ in
                await artworkInvocations.record()
                return ManagedArtworkRecoveryResult(
                    recoveredOperationIDs: [UUID()],
                    rolledBackOperationIDs: [],
                    effects: [effect]
                )
            },
            managedRecoveryCheckpoint: { phase in
                guard phase == checkpointPhase else {
                    return
                }
                await checkpoint.suspend()
            }
        )
    }

    func startRecovery() -> Task<Void, Never> {
        Task { @MainActor in
            await model.recoverManagedLibraryIfNeeded()
        }
    }

    func activateLibraryB() async throws {
        try await session.activate(repository: libraryBRepository)
    }

    func removeDirectory() {
        try? FileManager.default.removeItem(at: directory)
    }
}

actor FailOnceLyricsLifecycleIndexer: LyricsSearchIndexing {
    private var closeCount = 0

    func synchronize() async throws {}

    func synchronize(trackIDs _: Set<UUID>) async throws {}

    func search(
        query _: String,
        limit _: Int
    ) async throws -> [LyricsSearchMatch] {
        []
    }

    func close() async throws {
        closeCount += 1
        if closeCount == 1 {
            throw LyricsLifecycleProbeError.closeFailure
        }
    }
}

@MainActor
struct ManagedImportActivationRaceContext {
    let libraryBRepository: LibraryRepository
    let failureCheckpoint = LibraryEpochResultGate(())
    let session: LibrarySession
    let model: CadenceAppModel

    static func make() async throws -> Self {
        let oldLibrary = try LibraryEpochFixture(title: "Old Library")
        let importLibrary = try LibraryEpochFixture(title: "Import Library")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let session = LibrarySession.preview()
        try await session.store.attach(
            repository: oldLibrary.repository,
            lyricsSearchIndexer: FailOnceLyricsLifecycleIndexer()
        )
        session.availability = .ready
        let destination = ManagedLibraryImportDestination(
            package: makeEpochDummyPackage(label: "Import-Activation-Race"),
            repository: importLibrary.repository
        )
        let model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .available,
            librarySession: session,
            importDestination: destination
        )
        return Self(
            libraryBRepository: libraryB.repository,
            session: session,
            model: model
        )
    }
}
