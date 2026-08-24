import AppKit
@testable import Cadence
import Foundation
import ImageIO
import SwiftData
import SwiftUI
import Testing

@MainActor
struct MediaArtworkTests {
    @Test("Compact artwork data is downsampled to the thumbnail budget")
    func thumbnailBudget() throws {
        let representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 2048,
                pixelsHigh: 1024,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let source = try #require(
            representation.representation(using: .png, properties: [:])
        )
        let thumbnail = try #require(
            ArtworkThumbnailGenerator.data(
                from: source,
                maximumPixelDimension: 512
            )
        )
        let imageSource = try #require(
            CGImageSourceCreateWithData(thumbnail as CFData, nil)
        )
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
                as? [CFString: Any]
        )
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)

        #expect(max(width, height) == 512)
    }

    @Test("Track-row decode enforces its final pixel budget")
    func trackRowDecodeEnforcesPixelCap() throws {
        let data = try largeArtworkData()
        let asset = ArtworkAsset(
            data: data,
            variant: .trackRow
        )
        let image = try #require(ArtworkImageDecoder.image(for: asset))

        #expect(max(image.width, image.height) <= 128)
        #expect(
            ArtworkImageDecoder.decodedByteCost(of: image)
                <= 128 * 128 * 4
        )
    }

    @Test("Stored artwork bytes reach the final track-row decoder unchanged")
    func storedArtworkSkipsIntermediateReencoding() async throws {
        let fixture = try ArtworkLoadFixture(data: largeArtworkData())
        defer { fixture.remove() }

        let asset = try #require(
            await fixture.store.artworkAsset(
                id: fixture.artworkID,
                location: fixture.location,
                variant: .trackRow
            )
        )

        #expect(asset.data == fixture.data)
        #expect(asset.variant == .trackRow)
    }

    @Test("Cancelling the only artwork waiter publishes nothing")
    func cancellingOnlyArtworkWaiterPublishesNothing() async throws {
        let fixture = try ArtworkLoadFixture(data: largeArtworkData())
        defer { fixture.remove() }
        let probe = ArtworkDataLoadProbe(
            data: fixture.data,
            invocationCapacity: 1
        )
        let request = Task { @MainActor in
            await fixture.store.artworkAsset(
                id: fixture.artworkID,
                location: fixture.location,
                variant: .trackRow,
                dataLoader: probe.loader
            )
        }
        await Task.detached {
            probe.waitUntilStarted(invocation: 0)
        }.value

        request.cancel()
        for _ in 0 ..< 100 where !fixture.store.artworkDataLoads.isEmpty {
            await Task.yield()
        }
        let inFlightLoadWasReleased = fixture.store.artworkDataLoads.isEmpty
        probe.release(invocation: 0)
        let asset = await request.value

        #expect(inFlightLoadWasReleased)
        #expect(probe.observedCancellation(invocation: 0) == true)
        #expect(asset == nil)
        #expect(
            fixture.store.artworkAssetCache.asset(
                id: fixture.artworkID,
                revision: 0,
                variant: .trackRow
            ) == nil
        )
        #expect(fixture.store.operationFailure == nil)
    }

    @Test("Cancelling one shared artwork waiter keeps the producer alive")
    func cancellingSharedArtworkWaiterKeepsProducerAlive() async throws {
        let fixture = try ArtworkLoadFixture(data: largeArtworkData())
        defer { fixture.remove() }
        let probe = ArtworkDataLoadProbe(
            data: fixture.data,
            invocationCapacity: 1
        )
        let first = Task { @MainActor in
            await fixture.store.artworkAsset(
                id: fixture.artworkID,
                location: fixture.location,
                variant: .trackRow,
                dataLoader: probe.loader
            )
        }
        await Task.detached {
            probe.waitUntilStarted(invocation: 0)
        }.value
        let second = Task { @MainActor in
            await fixture.store.artworkAsset(
                id: fixture.artworkID,
                location: fixture.location,
                variant: .trackRow,
                dataLoader: probe.loader
            )
        }
        for _ in 0 ..< 100
            where fixture.store.artworkDataLoads.values.first?.waiterIDs.count != 2 {
            await Task.yield()
        }
        let waiterCount = fixture.store.artworkDataLoads.values.first?
            .waiterIDs.count

        first.cancel()
        for _ in 0 ..< 100
            where fixture.store.artworkDataLoads.values.first?.waiterIDs.count != 1 {
            await Task.yield()
        }
        probe.release(invocation: 0)
        let firstAsset = await first.value
        let secondAsset = await second.value

        #expect(waiterCount == 2)
        #expect(probe.invocationCount == 1)
        #expect(probe.observedCancellation(invocation: 0) == false)
        #expect(firstAsset == nil)
        #expect(secondAsset?.data == fixture.data)
        #expect(fixture.store.operationFailure == nil)
        #expect(fixture.store.artworkDataLoads.isEmpty)
    }

    @Test("A cancelled artwork load cannot retire its replacement")
    func cancelledArtworkLoadCannotRetireReplacement() async throws {
        let fixture = try ArtworkLoadFixture(data: largeArtworkData())
        defer { fixture.remove() }
        let probe = ArtworkDataLoadProbe(
            data: fixture.data,
            invocationCapacity: 2
        )
        let cancelled = Task { @MainActor in
            await fixture.store.artworkAsset(
                id: fixture.artworkID,
                location: fixture.location,
                variant: .trackRow,
                dataLoader: probe.loader
            )
        }
        await Task.detached {
            probe.waitUntilStarted(invocation: 0)
        }.value

        cancelled.cancel()
        for _ in 0 ..< 100 where !fixture.store.artworkDataLoads.isEmpty {
            await Task.yield()
        }
        let cancelledEntryWasRetired = fixture.store.artworkDataLoads.isEmpty
        let replacement = Task { @MainActor in
            await fixture.store.artworkAsset(
                id: fixture.artworkID,
                location: fixture.location,
                variant: .trackRow,
                dataLoader: probe.loader
            )
        }
        let replacementStarted = await Task.detached {
            probe.waitUntilStarted(
                invocation: 1,
                timeout: .now() + 2
            )
        }.value
        let replacementToken = fixture.store.artworkDataLoads.values.first?
            .token

        probe.release(invocation: 0)
        let cancelledAsset = await cancelled.value
        let replacementStayedTracked = replacementToken != nil
            && fixture.store.artworkDataLoads.values.first?.token
            == replacementToken
        probe.release(invocation: 1)
        let replacementAsset = await replacement.value

        #expect(cancelledEntryWasRetired)
        #expect(replacementStarted)
        #expect(cancelledAsset == nil)
        #expect(replacementStayedTracked)
        #expect(probe.invocationCount == 2)
        #expect(replacementAsset?.data == fixture.data)
        #expect(fixture.store.operationFailure == nil)
        #expect(fixture.store.artworkDataLoads.isEmpty)
    }

    @Test("Concurrent requests for the same artwork decode once")
    func sameArtworkKeyDecodesOnce() async throws {
        let cache = ArtworkImageCache()
        let data = try largeArtworkData()
        let asset = ArtworkAsset(
            data: data,
            variant: .trackRow
        )

        async let first = cache.image(for: asset)
        async let second = cache.image(for: asset)
        let images = await (first, second)
        let metrics = await cache.metrics()

        #expect(images.0 != nil)
        #expect(images.1 != nil)
        #expect(metrics.decodeInvocations == 1)
    }

    @Test("A cancelled queued artwork never reaches decode")
    func cancelledQueuedArtworkSkipsDecode() async throws {
        let cache = ArtworkImageCache()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let blocker = Task.detached {
            await cache.blockDecoderQueue(
                entered: entered,
                release: release
            )
        }
        await Task.detached {
            waitSynchronously(on: entered)
        }.value

        let data = try largeArtworkData()
        let cancelledAsset = ArtworkAsset(
            id: UUID(),
            data: data,
            variant: .trackRow
        )
        let liveAsset = ArtworkAsset(
            id: UUID(),
            data: data,
            variant: .trackRow
        )
        let started = DispatchSemaphore(value: 0)
        let cancelled = Task.detached {
            started.signal()
            return await cache.image(for: cancelledAsset)
        }
        await Task.detached {
            waitSynchronously(on: started)
        }.value
        cancelled.cancel()
        let live = Task.detached {
            await cache.image(for: liveAsset)
        }

        release.signal()
        await blocker.value
        let cancelledImage = await cancelled.value
        let liveImage = await live.value
        let metrics = await cache.metrics()

        #expect(cancelledImage == nil)
        #expect(liveImage != nil)
        #expect(metrics.decodeInvocations == 1)
    }

    private func largeArtworkData() throws -> Data {
        let representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 2048,
                pixelsHigh: 1024,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        return try #require(
            representation.representation(using: .png, properties: [:])
        )
    }
}

@MainActor
struct MediaArtworkPresentationTests {
    @Test(
        "Recycling hosted rows without artwork starts no artwork tasks",
        .appKitExclusive
    )
    func nilArtworkRecycleStartsNoTasks() async {
        let taskProbe = ProductionArtworkWorkProbe()
        let readyProbe = ArtworkReadyProbe()
        let model = CadenceAppModel.testFixture()
        let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }

        for recycle in 0 ..< 100 {
            hostingView.rootView = AnyView(
                ProductionArtworkView(
                    model: model,
                    artworkID: nil,
                    title: "No artwork \(recycle)",
                    placeholder: .track,
                    variant: .trackRow,
                    onReady: {
                        readyProbe.recordReady()
                    },
                    workProbe: taskProbe
                )
                .id(recycle)
                .frame(width: 40, height: 40)
            )
            hostingView.layoutSubtreeIfNeeded()
            for _ in 0 ..< 100 where readyProbe.readyCount <= recycle {
                await Task.yield()
            }
            #expect(readyProbe.readyCount == recycle + 1)
        }

        #expect(taskProbe.taskStarts == 0)
    }

    @Test("A superseded artwork request cannot publish")
    func supersededArtworkRequestCannotPublish() {
        let state = ProductionArtworkLoadState()
        let firstRequest = ProductionArtworkRequest(
            artworkID: UUID(),
            variant: .trackRow
        )
        let secondRequest = ProductionArtworkRequest(
            artworkID: UUID(),
            variant: .trackRow
        )
        let firstAsset = ArtworkAsset(data: Data([1]))
        let secondAsset = ArtworkAsset(data: Data([2]))
        let firstGeneration = state.begin(request: firstRequest)
        let secondGeneration = state.begin(request: secondRequest)

        #expect(
            state.publish(
                secondAsset,
                request: secondRequest,
                generation: secondGeneration
            )
        )
        #expect(
            !state.publish(
                firstAsset,
                request: firstRequest,
                generation: firstGeneration
            )
        )
        #expect(state.asset == secondAsset)
        #expect(state.publications == 1)
    }

    @Test("A completed nil artwork request remains completed")
    func completedNilArtworkRequestDoesNotRequireReload() {
        let state = ProductionArtworkLoadState()
        let request = ProductionArtworkRequest(
            artworkID: UUID(),
            variant: .trackRow
        )
        let generation = state.begin(request: request)

        #expect(
            state.publish(
                nil,
                request: request,
                generation: generation
            )
        )
        #expect(state.asset(for: request) == nil)
        #expect(state.hasCompleted(request))
        #expect(state.requestStarts == 1)
        #expect(state.publications == 1)
    }

    @Test("A changed artwork request invalidates completed nil state")
    func changedArtworkRequestStartsAndRejectsStalePublication() {
        let state = ProductionArtworkLoadState()
        let firstRequest = ProductionArtworkRequest(
            artworkID: UUID(),
            variant: .trackRow
        )
        let secondRequest = ProductionArtworkRequest(
            artworkID: UUID(),
            variant: .thumbnail
        )
        let firstGeneration = state.begin(request: firstRequest)
        #expect(
            state.publish(
                nil,
                request: firstRequest,
                generation: firstGeneration
            )
        )
        #expect(state.hasCompleted(firstRequest))
        #expect(!state.hasCompleted(secondRequest))

        let secondGeneration = state.begin(request: secondRequest)
        #expect(!state.hasCompleted(firstRequest))
        #expect(!state.hasCompleted(secondRequest))
        #expect(
            !state.publish(
                ArtworkAsset(data: Data([1])),
                request: firstRequest,
                generation: firstGeneration
            )
        )
        #expect(
            state.publish(
                nil,
                request: secondRequest,
                generation: secondGeneration
            )
        )
        #expect(state.hasCompleted(secondRequest))
        #expect(state.asset(for: firstRequest) == nil)
        #expect(state.asset(for: secondRequest) == nil)
        #expect(state.requestStarts == 2)
        #expect(state.publications == 2)
    }

    @Test("Artist artwork resolves custom image before placeholder")
    func artistPrecedence() {
        let asset = ArtworkAsset(data: Data([1]))

        #expect(
            ArtworkResolver.artist(custom: asset) == .custom(asset)
        )
        #expect(
            ArtworkResolver.artist(custom: nil) == .placeholder(.artist)
        )
    }

    @Test("Album artwork resolves custom, catalog, then placeholder")
    func albumPrecedence() {
        let asset = ArtworkAsset(data: Data([1]))

        #expect(
            ArtworkResolver.album(
                custom: asset,
                catalog: .ocean
            ) == .custom(asset)
        )
        #expect(
            ArtworkResolver.album(
                custom: nil,
                catalog: .ocean
            ) == .catalog(.ocean)
        )
        #expect(
            ArtworkResolver.album(
                custom: nil,
                catalog: nil
            ) == .placeholder(.album)
        )
    }

    @Test("Track inherits usable album artwork but not album placeholder")
    func trackPrecedence() {
        let trackAsset = ArtworkAsset(data: Data([1]))
        let albumAsset = ArtworkAsset(data: Data([2]))

        #expect(
            ArtworkResolver.track(
                custom: trackAsset,
                albumCustom: albumAsset,
                albumCatalog: .forest
            ) == .custom(trackAsset)
        )
        #expect(
            ArtworkResolver.track(
                custom: nil,
                albumCustom: albumAsset,
                albumCatalog: .forest
            ) == .custom(albumAsset)
        )
        #expect(
            ArtworkResolver.track(
                custom: nil,
                albumCustom: nil,
                albumCatalog: .forest
            ) == .catalog(.forest)
        )
        #expect(
            ArtworkResolver.track(
                custom: nil,
                albumCustom: nil,
                albumCatalog: nil
            ) == .placeholder(.track)
        )
    }

    @Test("Repository instances do not leak artwork state")
    func repositoryIsolation() {
        let first = InMemoryArtworkRepository()
        let second = InMemoryArtworkRepository()
        let target = ArtworkTarget.album("album")
        let asset = ArtworkAsset(data: Data([1]))

        first.setAsset(asset, for: target)

        #expect(first.asset(for: target) == asset)
        #expect(second.asset(for: target) == nil)
    }

    @Test("Replacing a crop preserves identity and increments revision")
    func revision() {
        let first = ArtworkAsset(data: Data([1]))
        let second = first.replacingCrop(
            data: Data([2]),
            scale: 2,
            normalizedOffset: CGSize(width: 0.1, height: -0.1)
        )

        #expect(second.id == first.id)
        #expect(second.revision == first.revision + 1)
        #expect(second.data == Data([2]))
    }

    @Test("Crop offsets include scaled-to-fill overflow at minimum zoom")
    func cropFillOverflow() {
        let portrait = ArtworkCropGeometry(
            previewSize: 340,
            sourceSize: CGSize(width: 100, height: 200)
        )
        let landscape = ArtworkCropGeometry(
            previewSize: 340,
            sourceSize: CGSize(width: 200, height: 100)
        )

        #expect(
            portrait.maximumOffset(scale: 1)
                == CGSize(width: 0, height: 170)
        )
        #expect(
            portrait.clamped(
                CGSize(width: 80, height: 250),
                scale: 1
            ) == CGSize(width: 0, height: 170)
        )
        #expect(
            landscape.maximumOffset(scale: 1)
                == CGSize(width: 170, height: 0)
        )
    }

    @Test("Crop zoom expands movable range on both axes")
    func cropZoomOverflow() {
        let square = ArtworkCropGeometry(
            previewSize: 340,
            sourceSize: CGSize(width: 100, height: 100)
        )

        #expect(
            square.maximumOffset(scale: 2)
                == CGSize(width: 170, height: 170)
        )
        #expect(
            square.clamped(
                CGSize(width: -220, height: 80),
                scale: 2
            ) == CGSize(width: -170, height: 80)
        )
    }

    @Test("Album overrides flow to tracks until a track override exists")
    func modelInheritance() throws {
        let model = CadenceAppModel.testFixture()
        let track = try #require(model.tracks.first)
        let album = try #require(
            model.albums.first { $0.id == track.albumID }
        )

        model.setCustomArtwork(
            data: Data([1]),
            scale: 1,
            normalizedOffset: .zero,
            for: .album(album.id)
        )
        let inherited = try #require(
            model.customArtwork(for: .album(album.id))
        )
        #expect(model.resolvedArtwork(for: track) == .custom(inherited))

        model.setCustomArtwork(
            data: Data([2]),
            scale: 2,
            normalizedOffset: .zero,
            for: .track(track.id)
        )
        let trackOverride = try #require(
            model.customArtwork(for: .track(track.id))
        )
        #expect(
            model.resolvedArtwork(for: track) == .custom(trackOverride)
        )

        model.removeCustomArtwork(for: .track(track.id))
        #expect(model.resolvedArtwork(for: track) == .custom(inherited))
    }

    @Test("Removing an album override restores catalog fallback")
    func removeFallback() throws {
        let model = CadenceAppModel.testFixture()
        let album = try #require(
            model.albums.first { $0.artworkPalette != nil }
        )
        let catalog = try #require(album.artworkPalette)

        model.setCustomArtwork(
            data: Data([1]),
            scale: 1,
            normalizedOffset: .zero,
            for: .album(album.id)
        )
        model.removeCustomArtwork(for: .album(album.id))

        #expect(model.resolvedArtwork(for: album) == .catalog(catalog))
    }
}

private extension ArtworkImageCache {
    func blockDecoderQueue(
        entered: DispatchSemaphore,
        release: DispatchSemaphore
    ) {
        entered.signal()
        release.wait()
    }
}

private func waitSynchronously(on semaphore: DispatchSemaphore) {
    semaphore.wait()
}

private final class ArtworkDataLoadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let data: Data
    private let entered: [DispatchSemaphore]
    private let releases: [DispatchSemaphore]
    private var nextInvocation = 0
    private var cancellationObservations: [Bool?]

    init(data: Data, invocationCapacity: Int) {
        self.data = data
        entered = (0 ..< invocationCapacity).map { _ in
            DispatchSemaphore(value: 0)
        }
        releases = (0 ..< invocationCapacity).map { _ in
            DispatchSemaphore(value: 0)
        }
        cancellationObservations = Array(
            repeating: nil,
            count: invocationCapacity
        )
    }

    var loader: ArtworkDataLoader {
        ArtworkDataLoader { [self] _ in
            let invocation = locked {
                defer { nextInvocation += 1 }
                return nextInvocation
            }
            entered[invocation].signal()
            releases[invocation].wait()
            let wasCancelled = withUnsafeCurrentTask {
                $0?.isCancelled ?? false
            }
            locked {
                cancellationObservations[invocation] = wasCancelled
            }
            return data
        }
    }

    var invocationCount: Int {
        locked { nextInvocation }
    }

    func waitUntilStarted(invocation: Int) {
        entered[invocation].wait()
    }

    func waitUntilStarted(
        invocation: Int,
        timeout: DispatchTime
    ) -> Bool {
        entered[invocation].wait(timeout: timeout) == .success
    }

    func release(invocation: Int) {
        releases[invocation].signal()
    }

    func observedCancellation(invocation: Int) -> Bool? {
        locked { cancellationObservations[invocation] }
    }

    private func locked<Value>(_ operation: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

@MainActor
private struct ArtworkLoadFixture {
    let root: URL
    let location: ManagedLibraryLocation
    let store: LibraryStore
    let artworkID: UUID
    let data: Data

    init(data: Data) throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Artwork-Load-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        location = ManagedLibraryLocation(musicDirectory: root)
        let package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let artworkID = UUID()
        self.artworkID = artworkID
        self.data = data
        let relativePath = "Artwork/Thumbnails/\(artworkID.uuidString).png"
        context.insert(
            ArtworkRecord(
                id: artworkID,
                ownerKind: .track,
                ownerID: UUID(),
                relativeOriginalPath: relativePath,
                relativeThumbnailPath: relativePath,
                format: "png",
                pixelWidth: 2048,
                pixelHeight: 1024,
                contentHash: String(repeating: "a", count: 64)
            )
        )
        try context.save()
        try data.write(to: location.resolve(relativePath: relativePath))
        store = LibraryStore(container: container, package: package)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class ArtworkReadyProbe {
    private(set) var readyCount = 0

    func recordReady() {
        readyCount += 1
    }
}
