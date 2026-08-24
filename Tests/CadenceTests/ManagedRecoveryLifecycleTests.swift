@testable import Cadence
import Foundation
import Testing

@MainActor
struct ManagedRecoveryLifecycleTests {
    @Test("A recovery superseded before attachment cannot replace library B")
    func recoverySupersededBeforeAttachmentCannotReplaceLibraryB()
        async throws {
        let context = try ManagedRecoveryLifecycleTestContext.make(
            suspendingAt: .beforeAttachment
        )
        defer { context.removeDirectory() }
        let staleRecovery = context.startRecovery()
        await context.checkpoint.waitUntilSuspended()
        let recoveryGeneration = context.session.transitionGeneration
        let activationCompletions = LifecycleInvocationRecorder()
        let authoritativeActivation = Task { @MainActor in
            try await context.activateLibraryB()
            await activationCompletions.record()
        }
        await waitForLifecycleTransitionReservation(
            in: context.session,
            after: recoveryGeneration
        )
        await drainLifecycleTasks()

        #expect(await activationCompletions.invocationCount == 0)
        await context.checkpoint.resume()
        await staleRecovery.value
        try await authoritativeActivation.value

        #expect(context.session.availability == .ready)
        #expect(context.session.store.repository === context.libraryBRepository)
        #expect(context.session.store.tracks.map(\.title) == ["Library B"])
        #expect(context.model.artworkRevision == 0)
        #expect(await context.artworkInvocations.invocationCount == 0)
        #expect(context.session.transitionLease.isIdle)
    }

    @Test("A superseded recovery cannot replace the library or publish artwork")
    func supersededRecoveryCannotPublish() async throws {
        let context = try ManagedRecoveryLifecycleTestContext.make(
            suspendingAt: .beforePublication
        )
        defer { context.removeDirectory() }

        let staleRecovery = context.startRecovery()
        await context.checkpoint.waitUntilSuspended()
        let recoveryGeneration = context.session.transitionGeneration
        let preparationCompletions = LifecycleInvocationRecorder()
        let preparation = Task { @MainActor in
            try await context.session.prepareForLibraryReplacement()
            await preparationCompletions.record()
        }
        await waitForLifecycleTransitionReservation(
            in: context.session,
            after: recoveryGeneration
        )
        await drainLifecycleTasks()

        #expect(await preparationCompletions.invocationCount == 0)
        await context.checkpoint.resume()
        await staleRecovery.value
        try await preparation.value

        #expect(context.session.availability == .recovering)
        #expect(context.session.store.repository == nil)
        #expect(context.session.store.tracks.isEmpty)
        #expect(context.model.artworkRevision == 0)
        #expect(await context.artworkInvocations.invocationCount == 1)
        #expect(context.session.transitionLease.isIdle)
    }

    @Test("A stale import activation failure cannot overwrite a newer library")
    func staleImportActivationFailureCannotOverwriteNewerLibrary()
        async throws {
        let context = try await ManagedImportActivationRaceContext.make()
        let staleActivation = Task { @MainActor in
            await context.model.activateManagedLibraryAfterImport {
                await context.failureCheckpoint.suspend()
            }
        }
        await context.failureCheckpoint.waitUntilSuspended()

        try await context.session.activate(
            repository: context.libraryBRepository
        )
        #expect(context.session.availability == .ready)

        await context.failureCheckpoint.resume()
        await staleActivation.value

        #expect(context.session.availability == .ready)
        #expect(context.session.store.repository === context.libraryBRepository)
        #expect(context.session.store.tracks.map(\.title) == ["Library B"])
        #expect(context.session.transitionLease.isIdle)
    }
}
