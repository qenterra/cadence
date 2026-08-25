import AppKit
@testable import Cadence
import Foundation
import Observation
import SwiftData
import SwiftUI
import Testing

@MainActor
func verifyFavoriteButtonTransientStateIsolation(
    tests: AllTracksPerformanceTests
) {
    let firstID = tests.deterministicUUID(592_001)
    let secondID = tests.deterministicUUID(592_002)
    var reusedState = FavoriteButtonTransientState(itemID: firstID)
    let firstRequest = reusedState.begin(isFavorite: false)

    #expect(firstRequest?.itemID == firstID)
    #expect(firstRequest?.requestedValue == true)
    #expect(reusedState.pendingValue == true)

    reusedState.reconcile(itemID: secondID)

    #expect(reusedState.itemID == secondID)
    #expect(reusedState.pendingValue == nil)
    #expect(reusedState.activeRequestToken == nil)

    var secondState = FavoriteButtonTransientState(itemID: secondID)
    let secondRequest = secondState.begin(isFavorite: false)
    let pendingSecondState = secondState

    if let firstRequest {
        secondState.complete(firstRequest, didSave: false)
    }
    #expect(secondState == pendingSecondState)

    if let secondRequest {
        secondState.complete(secondRequest, didSave: true)
    }
    #expect(secondState.pendingValue == nil)
    #expect(secondState.activeRequestToken == nil)
}

@MainActor
func verifyFavoriteButtonTokenReuseIsolation(
    tests: AllTracksPerformanceTests
) {
    let firstID = tests.deterministicUUID(592_101)
    let secondID = tests.deterministicUUID(592_102)
    var state = FavoriteButtonTransientState(itemID: firstID)
    let olderRequest = state.begin(isFavorite: false)

    state.reconcile(itemID: secondID)
    state.reconcile(itemID: firstID)
    let newerRequest = state.begin(isFavorite: false)
    let pendingNewerRequest = state

    if let olderRequest {
        state.complete(olderRequest, didSave: false)
    }
    #expect(state == pendingNewerRequest)

    if let newerRequest {
        state.complete(newerRequest, didSave: true)
    }
    #expect(state.pendingValue == nil)
    #expect(state.activeRequestToken == nil)
}

actor ScheduledFavoriteActionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var isSuspended = false

    func suspend() async {
        isSuspended = true
        suspensionWaiters.forEach { $0.resume() }
        suspensionWaiters.removeAll()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSuspended() async {
        guard !isSuspended else {
            return
        }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
struct ProductionFavoritePlaybackFixture {
    let firstTrackID: UUID
    let secondTrackID: UUID
    let repository: LibraryRepository
    let coordinator: PlaybackCoordinator
    let model: CadenceAppModel

    init() throws {
        let firstTrackID = UUID()
        let secondTrackID = UUID()
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let importSessionID = UUID()
        context.insert(
            ImportSessionRecord(
                id: importSessionID,
                sourceDisplayName: "Favorite playback fixture",
                state: .complete
            )
        )
        context.insert(
            Self.trackRecord(
                id: firstTrackID,
                title: "Track A",
                hashCharacter: "a",
                importSessionID: importSessionID
            )
        )
        context.insert(
            Self.trackRecord(
                id: secondTrackID,
                title: "Track B",
                hashCharacter: "b",
                importSessionID: importSessionID
            )
        )
        try context.save()

        let repository = LibraryRepository(modelContainer: container)
        let resolved = [
            playbackTestTrack(id: firstTrackID, title: "Track A"),
            playbackTestTrack(id: secondTrackID, title: "Track B"),
        ]
        let coordinator = makePlaybackCoordinator(
            resolver: PlaybackTestResolver(tracks: resolved),
            backends: [PlaybackTestBackend(kind: .pcm)]
        )
        let model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .unavailable("Not used by this test."),
            librarySession: .preview(),
            playbackCoordinator: coordinator
        )

        self.firstTrackID = firstTrackID
        self.secondTrackID = secondTrackID
        self.repository = repository
        self.coordinator = coordinator
        self.model = model
    }

    func startPlayback(at trackID: UUID) async throws {
        if model.librarySession.store.repository == nil {
            try await model.librarySession.activate(repository: repository)
        }
        await coordinator.startQueue(
            source: .adHoc,
            trackIDs: [firstTrackID, secondTrackID],
            startingAt: trackID
        )
    }

    func finish() async throws {
        model.shutdownPlayback()
        try await model.librarySession.store.detach()
    }

    private static func trackRecord(
        id: UUID,
        title: String,
        hashCharacter: Character,
        importSessionID: UUID
    ) -> TrackRecord {
        TrackRecord(
            id: id,
            originalFilename: "\(title).flac",
            title: title,
            duration: 180,
            codec: "FLAC",
            container: "FLAC",
            sampleRate: 48000,
            channelCount: 2,
            contentHash: String(repeating: hashCharacter, count: 64),
            relativeMediaPath: "Media/\(id.uuidString).flac",
            importSessionID: importSessionID
        )
    }
}

@MainActor
final class FavoriteButtonReuseFixture {
    private let state: FavoriteButtonReuseState
    private let lifecycle: FavoriteButtonLifecycleProbe
    private let hostingView: NSHostingView<FavoriteButtonReuseRoot>
    private let window: NSWindow

    init() {
        let state = FavoriteButtonReuseState(item: Self.item(name: "Track A"))
        let lifecycle = FavoriteButtonLifecycleProbe()
        let root = FavoriteButtonReuseRoot(
            state: state,
            lifecycle: lifecycle
        )
        let hostingView = NSHostingView(rootView: root)
        let frame = NSRect(x: 0, y: 0, width: 44, height: 44)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.state = state
        self.lifecycle = lifecycle
        self.hostingView = hostingView
        self.window = window
        hostingView.frame = frame
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFront(nil)
        settleAppKit()
    }

    func finish() {
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    func verifyStructuralReuse() {
        #expect(lifecycle.appearances == 1)
        #expect(lifecycle.disappearances == 0)

        state.item = Self.item(name: "Track B")
        settleAppKit()

        #expect(lifecycle.appearances == 1)
        #expect(lifecycle.disappearances == 0)
    }

    private func settleAppKit() {
        hostingView.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        _ = RunLoop.main.run(
            mode: .default,
            before: Date(timeIntervalSinceNow: 0.001)
        )
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private static func item(name: String) -> FavoriteButtonReuseItem {
        FavoriteButtonReuseItem(
            id: UUID(),
            name: name,
            isFavorite: false
        ) { _ in true }
    }
}

private struct FavoriteButtonReuseItem {
    let id: UUID
    let name: String
    let isFavorite: Bool
    let action: @Sendable (Bool) async -> Bool
}

@MainActor
@Observable
private final class FavoriteButtonReuseState {
    var item: FavoriteButtonReuseItem

    init(item: FavoriteButtonReuseItem) {
        self.item = item
    }
}

@MainActor
private final class FavoriteButtonLifecycleProbe {
    private(set) var appearances = 0
    private(set) var disappearances = 0

    func appear() {
        appearances += 1
    }

    func disappear() {
        disappearances += 1
    }
}

private struct FavoriteButtonReuseRoot: View {
    @Bindable var state: FavoriteButtonReuseState
    let lifecycle: FavoriteButtonLifecycleProbe

    var body: some View {
        let item = state.item
        FavoriteButton(
            itemID: item.id,
            isFavorite: item.isFavorite,
            itemName: item.name,
            controlSize: 44,
            action: item.action
        )
        .frame(width: 44, height: 44)
        .onAppear(perform: lifecycle.appear)
        .onDisappear(perform: lifecycle.disappear)
    }
}
