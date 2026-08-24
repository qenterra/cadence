@testable import Cadence
import Foundation
import Testing

enum LyricsLifecycleEvent: Hashable, Sendable {
    case started
    case cancelled
    case finished
    case closed
    case installedB
}

actor LifecycleInvocationRecorder {
    private(set) var invocationCount = 0

    func record() {
        invocationCount += 1
    }
}

@MainActor
func waitForLifecycleTransitionReservation(
    in session: LibrarySession,
    after generation: UInt64
) async {
    while session.transitionGeneration == generation {
        await Task.yield()
    }
}

@MainActor
func drainLifecycleTasks(turns: Int = 32) async {
    for _ in 0 ..< turns {
        await Task.yield()
    }
}

enum LyricsLifecycleProbeError: Error, LocalizedError, Sendable {
    case closeFailure

    var errorDescription: String? {
        "B index close failed."
    }
}

actor FailingCloseLyricsLifecycleIndexer: LyricsSearchIndexing {
    func synchronize() async throws {}

    func synchronize(trackIDs _: Set<UUID>) async throws {}

    func search(
        query _: String,
        limit _: Int
    ) async throws -> [LyricsSearchMatch] {
        []
    }

    func close() async throws {
        throw LyricsLifecycleProbeError.closeFailure
    }
}

@MainActor
func captureLifecycleTestError(
    _ operation: () async throws -> Void
) async -> (any Error)? {
    do {
        try await operation()
        Issue.record("Expected the operation to fail")
        return nil
    } catch {
        return error
    }
}

@MainActor
struct LyricsLifecycleReplacementTestContext {
    let libraryARepository: LibraryRepository
    let libraryBRepository: LibraryRepository
    let events: LyricsLifecycleEventRecorder
    let synchronizationGate: CancellableLyricsLifecycleGate
    let cleanupGate: LyricsLifecycleCleanupGate
    let replacementStarted: LyricsLifecycleSignal
    let indexerA: LyricsLifecycleIndexerProbe
    let indexerB: LyricsLifecycleIndexerProbe
    let store: LibraryStore
    let libraryAContext: LibraryStoreContext

    static func make() async throws -> Self {
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let events = LyricsLifecycleEventRecorder()
        let synchronizationGate = CancellableLyricsLifecycleGate()
        let cleanupGate = LyricsLifecycleCleanupGate()
        let replacementStarted = LyricsLifecycleSignal()
        let indexerA = LyricsLifecycleIndexerProbe(
            events: events,
            synchronizationGate: synchronizationGate,
            cleanupGate: cleanupGate,
            recordsLifecycle: true
        )
        let indexerB = LyricsLifecycleIndexerProbe(
            events: events,
            synchronizationGate: synchronizationGate,
            cleanupGate: cleanupGate,
            recordsLifecycle: false
        )
        let store = LibraryStore()
        try await store.attach(
            repository: libraryA.repository,
            lyricsSearchIndexer: indexerA
        )
        return Self(
            libraryARepository: libraryA.repository,
            libraryBRepository: libraryB.repository,
            events: events,
            synchronizationGate: synchronizationGate,
            cleanupGate: cleanupGate,
            replacementStarted: replacementStarted,
            indexerA: indexerA,
            indexerB: indexerB,
            store: store,
            libraryAContext: store.captureLibraryContext()
        )
    }
}

@MainActor
struct SessionLeaseOverlapTestContext {
    let libraryARepository: LibraryRepository
    let libraryBRepository: LibraryRepository
    let events: LyricsLifecycleEventRecorder
    let synchronizationGate: CancellableLyricsLifecycleGate
    let cleanupGate: LyricsLifecycleCleanupGate
    let session: LibrarySession

    static func make() async throws -> Self {
        let oldLibrary = try LibraryEpochFixture(title: "Old Library")
        let libraryA = try LibraryEpochFixture(title: "Library A")
        let libraryB = try LibraryEpochFixture(title: "Library B")
        let events = LyricsLifecycleEventRecorder()
        let synchronizationGate = CancellableLyricsLifecycleGate()
        let cleanupGate = LyricsLifecycleCleanupGate()
        let indexer = LyricsLifecycleIndexerProbe(
            events: events,
            synchronizationGate: synchronizationGate,
            cleanupGate: cleanupGate,
            recordsLifecycle: true
        )
        let session = LibrarySession.preview()
        try await session.store.attach(
            repository: oldLibrary.repository,
            lyricsSearchIndexer: indexer
        )
        return Self(
            libraryARepository: libraryA.repository,
            libraryBRepository: libraryB.repository,
            events: events,
            synchronizationGate: synchronizationGate,
            cleanupGate: cleanupGate,
            session: session
        )
    }
}

actor LyricsLifecycleEventRecorder {
    private(set) var values: [LyricsLifecycleEvent] = []
    private var eventWaiters:
        [LyricsLifecycleEvent: [CheckedContinuation<Void, Never>]] = [:]
    private var replacementWaiters:
        [CheckedContinuation<LyricsLifecycleEvent, Never>] = []

    func record(_ event: LyricsLifecycleEvent) {
        values.append(event)
        eventWaiters.removeValue(forKey: event)?.forEach { $0.resume() }
        guard event == .cancelled || event == .installedB else {
            return
        }
        replacementWaiters.forEach { $0.resume(returning: event) }
        replacementWaiters.removeAll()
    }

    func wait(for event: LyricsLifecycleEvent) async {
        guard !values.contains(event) else {
            return
        }
        await withCheckedContinuation { continuation in
            eventWaiters[event, default: []].append(continuation)
        }
    }

    func waitForCancellationOrInstallation() async -> LyricsLifecycleEvent {
        if let event = values.first(where: {
            $0 == .cancelled || $0 == .installedB
        }) {
            return event
        }
        return await withCheckedContinuation { continuation in
            replacementWaiters.append(continuation)
        }
    }
}

actor CancellableLyricsLifecycleGate {
    private var resumed = false

    func suspend() async throws {
        while !resumed {
            try Task.checkCancellation()
            await Task.yield()
        }
    }

    func resume() {
        resumed = true
    }
}

actor LyricsLifecycleCleanupGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumed = false

    func suspend() async {
        guard !resumed else {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        resumed = true
        continuation?.resume()
        continuation = nil
    }
}

actor LyricsLifecycleSignal {
    private var didFire = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func fire() {
        didFire = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func wait() async {
        guard !didFire else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

actor LyricsLifecycleIndexerProbe: LyricsSearchIndexing {
    private let events: LyricsLifecycleEventRecorder
    private let synchronizationGate: CancellableLyricsLifecycleGate
    private let cleanupGate: LyricsLifecycleCleanupGate
    private let recordsLifecycle: Bool

    init(
        events: LyricsLifecycleEventRecorder,
        synchronizationGate: CancellableLyricsLifecycleGate,
        cleanupGate: LyricsLifecycleCleanupGate,
        recordsLifecycle: Bool
    ) {
        self.events = events
        self.synchronizationGate = synchronizationGate
        self.cleanupGate = cleanupGate
        self.recordsLifecycle = recordsLifecycle
    }

    func synchronize() async throws {
        guard recordsLifecycle else {
            return
        }
        await events.record(.started)
        do {
            try await synchronizationGate.suspend()
        } catch is CancellationError {
            await events.record(.cancelled)
            await cleanupGate.suspend()
            await events.record(.finished)
            throw CancellationError()
        }
        await events.record(.finished)
    }

    func synchronize(trackIDs _: Set<UUID>) async throws {
        try await synchronize()
    }

    func search(
        query _: String,
        limit _: Int
    ) async throws -> [LyricsSearchMatch] {
        []
    }

    func close() async throws {
        guard recordsLifecycle else {
            return
        }
        await events.record(.closed)
    }
}

actor CancellableCloseLyricsLifecycleIndexer: LyricsSearchIndexing {
    private let closeStarted: LyricsLifecycleSignal
    private let closeGate: LyricsLifecycleCleanupGate

    init(
        closeStarted: LyricsLifecycleSignal,
        closeGate: LyricsLifecycleCleanupGate
    ) {
        self.closeStarted = closeStarted
        self.closeGate = closeGate
    }

    func synchronize() async throws {}

    func synchronize(trackIDs _: Set<UUID>) async throws {}

    func search(
        query _: String,
        limit _: Int
    ) async throws -> [LyricsSearchMatch] {
        []
    }

    func close() async throws {
        await closeStarted.fire()
        await closeGate.suspend()
        try Task.checkCancellation()
    }
}

func makeLifecyclePlaylist(
    id: UUID,
    name: String
) -> LibraryPlaylistProjection {
    LibraryPlaylistProjection(
        id: id,
        name: name,
        trackCount: 1,
        totalDuration: 180,
        modifiedAt: Date(timeIntervalSince1970: 1),
        customArtworkID: nil
    )
}

func makeLifecycleTrack(title: String) -> LibraryTrackProjection {
    LibraryTrackProjection(
        id: UUID(),
        title: title,
        artistID: nil,
        artist: "Artist",
        albumID: nil,
        album: "Album",
        duration: 180,
        year: 2026,
        codec: "ALAC",
        sampleRate: 48000,
        channelCount: 2,
        bitDepth: 24,
        isFavorite: false,
        customArtworkID: nil,
        artworkID: nil,
        relativeMediaPath: "Media/\(title).m4a",
        lastPlayedAt: nil,
        hasSynchronizedLyrics: false
    )
}

func makeLifecyclePlaylistClient(
    playlists: @escaping @Sendable () async throws
        -> [LibraryPlaylistProjection],
    tracks: [UUID: [LibraryTrackProjection]],
    remove: @escaping @Sendable (UUID, [UUID]) async throws -> Void = { _, _ in }
) -> LibraryPlaylistClient {
    LibraryPlaylistClient(
        playlists: playlists,
        playlistTracks: { tracks[$0] ?? [] },
        create: { name in
            makeLifecyclePlaylist(id: UUID(), name: name)
        },
        rename: { _, _ in },
        delete: { _ in },
        add: { _, _ in },
        remove: remove,
        reorder: { _, _ in },
        albumTrackIDs: { _ in [] },
        artistTrackIDs: { _ in [] }
    )
}
