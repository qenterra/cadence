@testable import Cadence
import Foundation
import Testing

@MainActor
struct LibrarySessionLifecycleTests {
    @Test("Overlapping activations retire safely and install the newest library")
    func overlappingActivationsInstallNewestLibrary() async throws {
        let context = try await SessionLeaseOverlapTestContext.make()
        let synchronization = Task { @MainActor in
            await context.session.store.synchronizeLyricsSearch()
        }
        await context.events.wait(for: .started)
        let activationA = Task { @MainActor in
            try await context.session.activate(
                repository: context.libraryARepository
            )
        }
        await context.events.wait(for: .cancelled)
        let generationA = context.session.transitionGeneration
        let activationB = Task { @MainActor in
            try await context.session.activate(
                repository: context.libraryBRepository
            )
        }
        await waitForLifecycleTransitionReservation(
            in: context.session,
            after: generationA
        )

        await context.synchronizationGate.resume()
        await context.cleanupGate.resume()
        await synchronization.value
        let errorA = await captureLifecycleTestError {
            try await activationA.value
        }
        try await activationB.value

        #expect(errorA is CancellationError)
        #expect(context.session.availability == .ready)
        #expect(
            context.session.store.repository === context.libraryBRepository
        )
        #expect(
            context.session.store.tracks.map(\.title) == ["Library B"]
        )
        #expect(context.session.transitionLease.isIdle)
    }

    @Test("A stale activation cannot mark a detached session ready")
    func staleActivationCannotMarkDetachedSessionReady() async throws {
        let library = try LibraryEpochFixture(title: "Library A")
        let snapshot = try await makeInitialEpochSnapshot(
            from: library.repository
        )
        let gate = LibraryEpochResultGate(snapshot)
        let session = LibrarySession.preview()
        let staleActivation = Task { @MainActor in
            try await session.activate(
                repository: library.repository,
                snapshotLoader: { _ in await gate.suspend() }
            )
        }
        await gate.waitUntilSuspended()
        let activationGeneration = session.transitionGeneration
        let preparation = Task { @MainActor in
            try await session.prepareForLibraryReplacement()
        }
        await waitForLifecycleTransitionReservation(
            in: session,
            after: activationGeneration
        )

        await gate.resume()
        let staleError = await captureLifecycleTestError {
            try await staleActivation.value
        }
        try await preparation.value

        #expect(staleError is CancellationError)
        #expect(session.availability == .recovering)
        #expect(session.store.repository == nil)
        #expect(session.store.availability == .empty)
        #expect(session.transitionLease.isIdle)
    }

    @Test("A superseded activation reports cancellation instead of success")
    func supersededActivationReportsCancellation() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let snapshotA = try await makeInitialEpochSnapshot(
            from: libraryA.repository
        )
        let gate = LibraryEpochResultGate(snapshotA)
        let session = LibrarySession.preview()
        let activationA = Task { @MainActor in
            try await session.activate(
                repository: libraryA.repository,
                snapshotLoader: { _ in await gate.suspend() }
            )
        }
        await gate.waitUntilSuspended()
        let generationA = session.transitionGeneration
        let activationB = Task { @MainActor in
            try await session.activate(repository: libraryB.repository)
        }
        await waitForLifecycleTransitionReservation(
            in: session,
            after: generationA
        )
        await gate.resume()
        let staleError = await captureLifecycleTestError {
            try await activationA.value
        }
        try await activationB.value

        #expect(staleError is CancellationError)
        #expect(session.availability == .ready)
        #expect(session.store.repository === libraryB.repository)
        #expect(session.store.tracks.map(\.title) == ["Library B"])
        #expect(session.transitionLease.isIdle)
    }

    @Test("Cancelling a queued activation cannot block the next activation")
    func cancellingQueuedActivationDoesNotBlockNextActivation() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let libraryC = try LibraryEpochFixture(title: "Library C")
        let snapshotA = try await makeInitialEpochSnapshot(
            from: libraryA.repository
        )
        let gate = LibraryEpochResultGate(snapshotA)
        let session = LibrarySession.preview()
        let activationA = Task { @MainActor in
            try await session.activate(
                repository: libraryA.repository,
                snapshotLoader: { _ in await gate.suspend() }
            )
        }
        await gate.waitUntilSuspended()
        let generationA = session.transitionGeneration
        let activationB = Task { @MainActor in
            try await session.activate(repository: libraryB.repository)
        }
        await waitForLifecycleTransitionReservation(
            in: session,
            after: generationA
        )
        activationB.cancel()
        let errorB = await captureLifecycleTestError {
            try await activationB.value
        }
        #expect(errorB is CancellationError)
        #expect(!session.transitionLease.isIdle)
        let generationB = session.transitionGeneration
        let activationC = Task { @MainActor in
            try await session.activate(repository: libraryC.repository)
        }
        await waitForLifecycleTransitionReservation(
            in: session,
            after: generationB
        )

        await gate.resume()
        let errorA = await captureLifecycleTestError {
            try await activationA.value
        }
        try await activationC.value

        #expect(errorA is CancellationError)
        #expect(errorB is CancellationError)
        #expect(session.availability == .ready)
        #expect(session.store.repository === libraryC.repository)
        #expect(session.store.tracks.map(\.title) == ["Library C"])
        #expect(session.transitionLease.isIdle)
    }
}

extension LibrarySessionLifecycleTests {
    @Test("Cancelling active retirement does not publish a session failure")
    func cancellingActiveRetirementDoesNotPublishFailure() async throws {
        let oldLibrary = try LibraryEpochFixture(title: "Old Library")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let closeStarted = LyricsLifecycleSignal()
        let closeGate = LyricsLifecycleCleanupGate()
        let indexer = CancellableCloseLyricsLifecycleIndexer(
            closeStarted: closeStarted,
            closeGate: closeGate
        )
        let session = LibrarySession.preview()
        try await session.store.attach(
            repository: oldLibrary.repository,
            lyricsSearchIndexer: indexer
        )
        session.availability = .ready

        let activation = Task { @MainActor in
            try await session.activate(repository: libraryB.repository)
        }
        await closeStarted.wait()
        activation.cancel()
        await closeGate.resume()
        let error = await captureLifecycleTestError {
            try await activation.value
        }

        #expect(error is CancellationError)
        if case .failed = session.availability {
            Issue.record("Cancellation must not publish an operational failure")
        }
        #expect(session.availability == .recovering)
        #expect(session.store.repository === oldLibrary.repository)
        #expect(session.transitionLease.isIdle)
    }

    @Test("The newest live FIFO waiter wins after stale waiters retire")
    func newestLiveFIFOWaiterWinsAfterStaleWaitersRetire() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let libraryC = try LibraryEpochFixture(title: "Library C")
        let snapshotA = try await makeInitialEpochSnapshot(
            from: libraryA.repository
        )
        let gate = LibraryEpochResultGate(snapshotA)
        let session = LibrarySession.preview()
        let activationA = Task { @MainActor in
            try await session.activate(
                repository: libraryA.repository,
                snapshotLoader: { _ in await gate.suspend() }
            )
        }
        await gate.waitUntilSuspended()
        let generationA = session.transitionGeneration
        let activationB = Task { @MainActor in
            try await session.activate(repository: libraryB.repository)
        }
        await waitForLifecycleTransitionReservation(
            in: session,
            after: generationA
        )
        let generationB = session.transitionGeneration
        let activationC = Task { @MainActor in
            try await session.activate(repository: libraryC.repository)
        }
        await waitForLifecycleTransitionReservation(
            in: session,
            after: generationB
        )

        await gate.resume()
        let errorA = await captureLifecycleTestError {
            try await activationA.value
        }
        let errorB = await captureLifecycleTestError {
            try await activationB.value
        }
        try await activationC.value

        #expect(errorA is CancellationError)
        #expect(errorB is CancellationError)
        #expect(session.availability == .ready)
        #expect(session.store.repository === libraryC.repository)
        #expect(session.store.tracks.map(\.title) == ["Library C"])
        #expect(session.transitionLease.isIdle)
    }

    @Test("A failed switch exposes a rollback retirement failure")
    func failedSwitchExposesRollbackRetirementFailure() async throws {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let session = LibrarySession.preview()
        try await session.activate(repository: libraryA.repository)
        let locationB = ManagedLibraryLocation(
            musicDirectory: FileManager.default.temporaryDirectory.appending(
                path: "Cadence-Lifecycle-B-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        )
        let failingIndexer = FailingCloseLyricsLifecycleIndexer()

        let error = await captureLifecycleTestError {
            try await session.switchLocation(
                to: locationB,
                repository: libraryB.repository,
                lyricsSearchIndexer: failingIndexer,
                snapshotLoader: { _ in
                    throw LibraryEpochTestError.staleOperation
                }
            )
        }

        #expect(
            error?.localizedDescription.contains(
                LyricsLifecycleProbeError.closeFailure.errorDescription ?? ""
            ) == true
        )
        guard case let .failed(failure) = session.availability else {
            Issue.record("Expected the session to fail closed")
            return
        }
        #expect(failure.message.contains("B index close failed"))
        #expect(session.location == locationB)
        #expect(session.store.repository === libraryB.repository)
    }
}
