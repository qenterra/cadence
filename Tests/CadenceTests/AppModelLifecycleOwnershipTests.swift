@testable import Cadence
import Testing

@MainActor
struct AppModelLifecycleOwnershipTests {
    @Test("A stale metadata repair cannot refresh or fail a newer library")
    func staleMetadataRepairCannotAffectNewerLibrary() async throws {
        try await verifyStaleMetadataRepairSuccess()
        try await verifyStaleMetadataRepairFailure()
    }

    @Test("A stale reset reopen failure cannot fail a newer library")
    func staleResetReopenFailureCannotFailNewerLibrary() async throws {
        let context = try await ResetReopenLifecycleTestContext.make()
        defer { context.removeDirectory() }
        let staleReopen = Task { @MainActor in
            await context.model.handleResetPreparationFailure(
                AppModelLifecycleTestError.staleOperation,
                location: context.location,
                failureCheckpoint: {
                    await context.failureCheckpoint.suspend()
                },
                reopenOperation: { _ in
                    throw AppModelLifecycleTestError.staleOperation
                }
            )
        }
        await context.failureCheckpoint.waitUntilSuspended()

        try await context.session.activate(
            repository: context.libraryBRepository
        )
        #expect(context.session.availability == .ready)

        await context.failureCheckpoint.resume()
        await staleReopen.value

        #expect(context.session.availability == .ready)
        #expect(context.session.store.repository === context.libraryBRepository)
        #expect(context.session.store.tracks.map(\.title) == ["Library B"])
        #expect(context.session.transitionLease.isIdle)
    }

    private func verifyStaleMetadataRepairSuccess() async throws {
        let context = try await MetadataRepairLifecycleTestContext.make()
        defer { context.removeDirectory() }
        let result = ManagedMetadataRepairResult(
            repairedCount: 1,
            failures: []
        )
        let gate = LibraryEpochResultGate(
            Result<ManagedMetadataRepairResult, AppModelLifecycleTestError>
                .success(result)
        )
        let staleRepair = Task { @MainActor in
            await context.model.repairImportedMetadataIfNeeded { _, _ in
                try await gate.suspend().get()
            }
        }
        await gate.waitUntilSuspended()
        try await context.activateLibraryB()
        let currentContentVersion = context.session.store
            .allTracksWindowContentVersion

        await gate.resume()
        let reportedResult = await staleRepair.value

        #expect(reportedResult == nil)
        #expect(context.session.availability == .ready)
        #expect(context.session.store.repository === context.libraryBRepository)
        #expect(
            context.session.store.allTracksWindowContentVersion
                == currentContentVersion
        )
    }

    private func verifyStaleMetadataRepairFailure() async throws {
        let context = try await MetadataRepairLifecycleTestContext.make()
        defer { context.removeDirectory() }
        let gate = LibraryEpochResultGate(
            Result<ManagedMetadataRepairResult, AppModelLifecycleTestError>
                .failure(.staleOperation)
        )
        let staleRepair = Task { @MainActor in
            await context.model.repairImportedMetadataIfNeeded { _, _ in
                try await gate.suspend().get()
            }
        }
        await gate.waitUntilSuspended()
        try await context.activateLibraryB()

        await gate.resume()
        let reportedResult = await staleRepair.value

        #expect(reportedResult == nil)
        #expect(context.session.availability == .ready)
        #expect(context.session.store.repository === context.libraryBRepository)
        #expect(context.session.store.tracks.map(\.title) == ["Library B"])
        #expect(context.session.transitionLease.isIdle)
    }
}
