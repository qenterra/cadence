@testable import Cadence
import Foundation
import Testing

@MainActor
struct LibraryResetLifecycleTests {
    @Test("A superseded pre-commit reset rolls back before the next activation")
    func supersededResetRollsBackBeforeNextActivation() async throws {
        let context = try await LibraryResetLifecycleTestContext.make()
        let preparedGate = LibraryEpochResultGate(())
        let rolledBackGate = LibraryEpochResultGate(())
        let snapshotLoads = LifecycleInvocationRecorder()
        let completions = LifecycleInvocationRecorder()
        let reset = Task { @MainActor in
            await context.model.deleteEntireManagedLibrary(
                checkpoint: { phase in
                    switch phase {
                    case .packagePrepared:
                        await preparedGate.suspend()
                    case .packageRolledBack:
                        await rolledBackGate.suspend()
                    case .locationCommitted:
                        break
                    }
                },
                replacementActivation: { _ in
                    throw LibraryResetLifecycleTestError
                        .replacementActivationFailed
                }
            )
        }
        await preparedGate.waitUntilSuspended()
        let resetGeneration = context.session.transitionGeneration
        let activationB = Task { @MainActor in
            try await context.activateLibraryB(
                snapshotLoads: snapshotLoads,
                completions: completions
            )
        }
        await waitForLifecycleTransitionReservation(
            in: context.session,
            after: resetGeneration
        )
        await drainLifecycleTasks()

        await expectNoActivation(snapshotLoads, completions)
        expectResetOwnsLease(context, generation: resetGeneration)

        await preparedGate.resume()
        await rolledBackGate.waitUntilSuspended()

        #expect(try context.package.readIdentity() == context.originalIdentity)
        #expect(FileManager.default.fileExists(atPath: context.markerURL.path))
        await expectNoActivation(snapshotLoads, completions)

        await rolledBackGate.resume()
        await reset.value
        try await activationB.value

        expectLibraryBInstalled(context)
        await context.removeArtifacts()
    }

    @Test("Cancelling a pre-commit reset restores the original library")
    func cancelledResetRestoresOriginalLibrary() async throws {
        let context = try await LibraryResetLifecycleTestContext.make()
        let preparedGate = LibraryEpochResultGate(())
        let reset = Task { @MainActor in
            await context.model.deleteEntireManagedLibrary(
                checkpoint: { phase in
                    guard case .packagePrepared = phase else {
                        return
                    }
                    await preparedGate.suspend()
                }
            )
        }
        await preparedGate.waitUntilSuspended()

        reset.cancel()
        await preparedGate.resume()
        await reset.value

        let restoredIdentity = try? context.package.readIdentity()
        #expect(restoredIdentity == context.originalIdentity)
        #expect(FileManager.default.fileExists(atPath: context.markerURL.path))
        #expect(try context.backupURLs().isEmpty)
        #expect(context.session.availability == .ready)
        #expect(context.session.transitionLease.isIdle)
        await context.removeArtifacts()
    }

    @Test("A cancelled queued successor leaves the reset able to restore the original library")
    func cancelledQueuedSuccessorRestoresOriginalLibrary() async throws {
        let context = try await LibraryResetLifecycleTestContext.make()
        let preparedGate = LibraryEpochResultGate(())
        let snapshotLoads = LifecycleInvocationRecorder()
        let completions = LifecycleInvocationRecorder()
        let reset = Task { @MainActor in
            await context.model.deleteEntireManagedLibrary(
                checkpoint: { phase in
                    guard case .packagePrepared = phase else {
                        return
                    }
                    await preparedGate.suspend()
                }
            )
        }
        await preparedGate.waitUntilSuspended()
        let resetGeneration = context.session.transitionGeneration
        let activationB = Task { @MainActor in
            try await context.activateLibraryB(
                snapshotLoads: snapshotLoads,
                completions: completions
            )
        }
        await waitForLifecycleTransitionReservation(
            in: context.session,
            after: resetGeneration
        )

        activationB.cancel()
        let successorError: (any Error)?
        do {
            try await activationB.value
            successorError = nil
        } catch {
            successorError = error
        }

        #expect(successorError is CancellationError)
        #expect(
            context.session.transitionLease.ownerGeneration
                == resetGeneration
        )

        await preparedGate.resume()
        await reset.value

        #expect(try context.package.readIdentity() == context.originalIdentity)
        #expect(FileManager.default.fileExists(atPath: context.markerURL.path))
        #expect(try context.backupURLs().isEmpty)
        #expect(context.session.availability == .ready)
        #expect(context.session.transitionLease.isIdle)
        await context.removeArtifacts()
    }

    @Test("A committed reset finishes before the next activation starts")
    func committedResetFinishesBeforeNextActivation() async throws {
        let context = try await LibraryResetLifecycleTestContext.make()
        let committedGate = LibraryEpochResultGate(())
        let snapshotLoads = LifecycleInvocationRecorder()
        let completions = LifecycleInvocationRecorder()
        let reset = Task { @MainActor in
            await context.model.deleteEntireManagedLibrary(
                checkpoint: { phase in
                    guard case .locationCommitted = phase else {
                        return
                    }
                    await committedGate.suspend()
                }
            )
        }
        await committedGate.waitUntilSuspended()
        let backupURL = try #require(context.backupURLs().first)
        let resetGeneration = context.session.transitionGeneration
        let activationB = Task { @MainActor in
            try await context.activateLibraryB(
                snapshotLoads: snapshotLoads,
                completions: completions
            )
        }
        await waitForLifecycleTransitionReservation(
            in: context.session,
            after: resetGeneration
        )
        await drainLifecycleTasks()

        let snapshotLoadCount = await snapshotLoads.invocationCount
        let completionCount = await completions.invocationCount
        #expect(snapshotLoadCount == 0)
        #expect(completionCount == 0)
        #expect(
            context.session.transitionLease.ownerGeneration
                == resetGeneration
        )
        #expect(FileManager.default.fileExists(atPath: backupURL.path))

        await committedGate.resume()
        await reset.value
        try await activationB.value

        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
        #expect(try context.package.readIdentity() != context.originalIdentity)
        #expect(context.session.availability == .ready)
        #expect(context.session.store.repository === context.libraryBRepository)
        #expect(context.session.store.tracks.map(\.title) == ["Library B"])
        #expect(context.session.transitionLease.isIdle)
        await context.removeArtifacts()
    }
}

private extension LibraryResetLifecycleTests {
    func expectNoActivation(
        _ snapshotLoads: LifecycleInvocationRecorder,
        _ completions: LifecycleInvocationRecorder
    ) async {
        let snapshotLoadCount = await snapshotLoads.invocationCount
        let completionCount = await completions.invocationCount
        #expect(snapshotLoadCount == 0)
        #expect(completionCount == 0)
    }

    func expectResetOwnsLease(
        _ context: LibraryResetLifecycleTestContext,
        generation: UInt64
    ) {
        #expect(
            context.session.transitionLease.ownerGeneration
                == generation
        )
    }

    func expectLibraryBInstalled(
        _ context: LibraryResetLifecycleTestContext
    ) {
        #expect(context.session.availability == .ready)
        #expect(
            context.session.store.repository
                === context.libraryBRepository
        )
        #expect(
            context.session.store.tracks.map(\.title)
                == ["Library B"]
        )
        #expect(context.session.transitionLease.isIdle)
    }
}
