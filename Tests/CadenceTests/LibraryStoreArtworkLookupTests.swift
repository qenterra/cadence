@testable import Cadence
import Foundation
import Testing

@MainActor
struct LibraryStoreArtworkLookupTests {
    private let requestCount = 12

    @Test("A warm artwork asset skips repeated metadata and data lookup")
    func warmArtworkAssetSkipsRepeatedMetadataLookup() async throws {
        let context = try ArtworkLookupContext()
        let metadata = CountingArtworkMetadataProbe(
            outcome: .projection(context.projection(path: "Artwork/A.png"))
        )
        let data = CountingArtworkDataProbe(data: context.dataA)
        try await context.store.attach(repository: context.libraryA.repository)

        var assets: [ArtworkAsset?] = []
        for _ in 0 ..< requestCount {
            await assets.append(
                context.store.artworkAsset(
                    id: context.artworkID,
                    location: context.location,
                    metadataLoader: metadata.loader,
                    dataLoader: data.loader
                )
            )
        }

        #expect(assets.allSatisfy { $0?.data == context.dataA })
        #expect(await metadata.invocationCount == 1)
        #expect(data.invocationCount == 1)
    }

    @Test("Concurrent artwork requests share one metadata producer")
    func concurrentArtworkRequestsShareMetadataProducer() async throws {
        let context = try ArtworkLookupContext()
        let metadata = GatedArtworkMetadataProbe(
            outcome: .projection(context.projection(path: "Artwork/A.png"))
        )
        let data = GatedArtworkDataProbe(data: context.dataA)
        try await context.store.attach(repository: context.libraryA.repository)

        let requests = (0 ..< requestCount).map { _ in
            Task { @MainActor in
                await context.store.artworkAsset(
                    id: context.artworkID,
                    location: context.location,
                    metadataLoader: metadata.loader,
                    dataLoader: data.loader
                )
            }
        }
        await metadata.waitUntilStarted()
        await settleConcurrentRequests()

        #expect(await metadata.invocationCount == 1)

        await metadata.releaseAll()
        await data.waitUntilStarted()
        await waitForArtworkDataWaiters(
            requestCount,
            store: context.store
        )
        #expect(
            context.store.artworkDataLoads.values.first?.waiterIDs.count
                == requestCount
        )

        data.release()
        let assets = await values(of: requests)
        #expect(assets.count == requestCount)
        #expect(assets.allSatisfy { $0?.data == context.dataA })
        #expect(data.invocationCount == 1)
    }

    @Test("Artwork lookup state retires on publication and library reattach")
    func artworkLookupStateRetiresOnPublicationAndReattach() async throws {
        try await verifyPublicationRetiresLookupState()
        try await verifyReattachRejectsStaleResult()
        try await verifyReattachRejectsStaleError()
    }

    private func verifyPublicationRetiresLookupState() async throws {
        let context = try ArtworkLookupContext()
        let metadataA = CountingArtworkMetadataProbe(
            outcome: .projection(context.projection(path: "Artwork/A.png"))
        )
        let dataA = GatedArtworkDataProbe(data: context.dataA)
        try await context.store.attach(
            repository: context.libraryA.repository,
            package: context.package
        )
        let staleRequest = Task { @MainActor in
            await context.store.artworkAsset(
                id: context.artworkID,
                location: context.location,
                metadataLoader: metadataA.loader,
                dataLoader: dataA.loader
            )
        }
        await dataA.waitUntilStarted()

        try await publishReplacement(in: context)

        #expect(context.store.artworkDataLoads.isEmpty)
        dataA.release()
        let staleAsset = await staleRequest.value
        #expect(staleAsset == nil)
        #expect(dataA.observedCancellation == true)
        #expect(context.store.operationFailure == nil)
        #expect(context.cachedAsset == nil)

        try await verifyCurrentBAsset(in: context)
    }

    private func verifyReattachRejectsStaleResult() async throws {
        let context = try ArtworkLookupContext()
        let staleMetadata = GatedArtworkMetadataProbe(
            outcome: .projection(context.projection(path: "Artwork/A.png"))
        )
        let dataA = CountingArtworkDataProbe(data: context.dataA)
        try await context.store.attach(repository: context.libraryA.repository)
        let staleRequest = Task { @MainActor in
            await context.store.artworkAsset(
                id: context.artworkID,
                location: context.location,
                metadataLoader: staleMetadata.loader,
                dataLoader: dataA.loader
            )
        }
        await staleMetadata.waitUntilStarted()
        context.store.artworkAssetCache.insert(context.unrelatedWarmAsset)

        let replacement = Task { @MainActor in
            try await context.store.attach(repository: context.libraryB.repository)
        }
        await waitForArtworkRetirement(in: context.store)
        #expect(context.store.artworkAssetCache.isEmpty)
        await staleMetadata.releaseAll()
        try await replacement.value
        let staleAsset = await staleRequest.value

        #expect(staleAsset == nil)
        #expect(context.cachedAsset == nil)
        #expect(context.store.operationFailure == nil)
        try await verifyCurrentBAsset(in: context)
    }

    private func verifyReattachRejectsStaleError() async throws {
        let context = try ArtworkLookupContext()
        let staleMetadata = GatedArtworkMetadataProbe(outcome: .failure)
        try await context.store.attach(repository: context.libraryA.repository)
        let staleRequest = Task { @MainActor in
            await context.store.artworkAsset(
                id: context.artworkID,
                location: context.location,
                metadataLoader: staleMetadata.loader
            )
        }
        await staleMetadata.waitUntilStarted()

        let replacement = Task { @MainActor in
            try await context.store.attach(repository: context.libraryB.repository)
        }
        await waitForArtworkRetirement(in: context.store)
        await staleMetadata.releaseAll()
        try await replacement.value
        let staleAsset = await staleRequest.value

        #expect(staleAsset == nil)
        #expect(context.cachedAsset == nil)
        #expect(context.store.operationFailure == nil)
    }

    private func publishReplacement(
        in context: ArtworkLookupContext
    ) async throws {
        let effect = ManagedArtworkPublicationEffect(
            ownerKind: .smartCollection,
            ownerID: UUID(),
            previousArtworkID: context.artworkID,
            newArtworkID: context.artworkID
        )
        try await context.store.setArtwork(
            ManagedArtworkEditRequest(
                ownerKind: effect.ownerKind,
                ownerID: effect.ownerID,
                data: context.dataB,
                scale: 1,
                normalizedOffset: .zero
            ),
            location: context.location,
            operation: { _, _ in
                ManagedArtworkMutationResult(
                    primaryArtworkID: context.artworkID,
                    effects: [effect]
                )
            }
        )
    }

    private func verifyCurrentBAsset(
        in context: ArtworkLookupContext
    ) async throws {
        let metadataB = CountingArtworkMetadataProbe(
            outcome: .projection(context.projection(path: "Artwork/B.png"))
        )
        let dataB = CountingArtworkDataProbe(data: context.dataB)

        let asset = await context.store.artworkAsset(
            id: context.artworkID,
            location: context.location,
            metadataLoader: metadataB.loader,
            dataLoader: dataB.loader
        )

        #expect(asset?.data == context.dataB)
        #expect(context.cachedAsset?.data == context.dataB)
        #expect(await metadataB.invocationCount == 1)
        #expect(dataB.invocationCount == 1)
        #expect(context.store.operationFailure == nil)
    }

    private func settleConcurrentRequests() async {
        for _ in 0 ..< 100 {
            await Task.yield()
        }
    }

    private func waitForArtworkRetirement(in store: LibraryStore) async {
        for _ in 0 ..< 100 where store.attachmentPhase != .retiring {
            await Task.yield()
        }
        #expect(store.attachmentPhase == .retiring)
    }

    private func waitForArtworkDataWaiters(
        _ count: Int,
        store: LibraryStore
    ) async {
        for _ in 0 ..< 100
            where store.artworkDataLoads.values.first?.waiterIDs.count != count {
            await Task.yield()
        }
    }

    private func values(
        of tasks: [Task<ArtworkAsset?, Never>]
    ) async -> [ArtworkAsset?] {
        var values: [ArtworkAsset?] = []
        for task in tasks {
            await values.append(task.value)
        }
        return values
    }
}

@MainActor
private struct ArtworkLookupContext {
    let store = LibraryStore()
    let libraryA: LibraryEpochFixture
    let libraryB: LibraryEpochFixture
    let artworkID = UUID()
    let unrelatedArtworkID = UUID()
    let package: ManagedLibraryPackage
    let dataA = Data([0xA1])
    let dataB = Data([0xB2])

    init() throws {
        libraryA = try LibraryEpochFixture(title: "Artwork Library A")
        libraryB = try LibraryEpochFixture(title: "Artwork Library B")
        package = makeEpochDummyPackage(label: "Artwork-Lookup")
    }

    var location: ManagedLibraryLocation {
        package.location
    }

    var cachedAsset: ArtworkAsset? {
        store.artworkAssetCache.asset(
            id: artworkID,
            revision: 0
        )
    }

    var unrelatedWarmAsset: ArtworkAsset {
        ArtworkAsset(
            id: unrelatedArtworkID,
            revision: 0,
            data: dataA
        )
    }

    func projection(path: String) -> ManagedArtworkProjection {
        ManagedArtworkProjection(
            id: artworkID,
            relativePath: path,
            revision: 0,
            scale: 1,
            normalizedOffsetX: 0,
            normalizedOffsetY: 0
        )
    }
}

private enum ArtworkMetadataOutcome: Sendable {
    case projection(ManagedArtworkProjection)
    case failure

    func get() throws -> ManagedArtworkProjection {
        switch self {
        case let .projection(projection):
            projection
        case .failure:
            throw ArtworkLookupTestError.staleMetadata
        }
    }
}

private actor CountingArtworkMetadataProbe {
    private let outcome: ArtworkMetadataOutcome
    private(set) var invocationCount = 0

    init(outcome: ArtworkMetadataOutcome) {
        self.outcome = outcome
    }

    nonisolated var loader: ArtworkMetadataLoader {
        ArtworkMetadataLoader { [self] _, _ in
            try await load()
        }
    }

    private func load() throws -> ManagedArtworkProjection {
        invocationCount += 1
        return try outcome.get()
    }
}

private actor GatedArtworkMetadataProbe {
    private let outcome: ArtworkMetadataOutcome
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false
    private(set) var invocationCount = 0

    init(outcome: ArtworkMetadataOutcome) {
        self.outcome = outcome
    }

    nonisolated var loader: ArtworkMetadataLoader {
        ArtworkMetadataLoader { [self] _, _ in
            try await load()
        }
    }

    func waitUntilStarted() async {
        guard invocationCount == 0 else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseAll() {
        isReleased = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }

    private func load() async throws -> ManagedArtworkProjection {
        invocationCount += 1
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        if !isReleased {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        return try outcome.get()
    }
}
