import AppKit
@testable import Cadence
import Foundation
import SwiftData
import SwiftUI
import Testing

extension AllTracksPerformanceTests {
    func configureAllTracksWindow(
        _ window: LibraryTrackWindow,
        store: LibraryStore
    ) async {
        await window.configure(
            totalCount: store.catalogCounts.liveTrackCount,
            query: store.trackQuery,
            contentVersion: store.allTracksWindowContentVersion
        )
    }

    func makeTrack(title: String) -> LibraryTrackProjection {
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
            relativeMediaPath: "first.m4a",
            lastPlayedAt: nil,
            hasSynchronizedLyrics: false
        )
    }

    func makeTracks(count: Int) -> [LibraryTrackProjection] {
        (0 ..< count).map { index in
            LibraryTrackProjection(
                id: deterministicUUID(index),
                title: String(format: "Track %05d", index),
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
                relativeMediaPath: "track-\(index).m4a",
                lastPlayedAt: nil,
                hasSynchronizedLyrics: false
            )
        }
    }

    func replacingArtworkID(
        _ track: LibraryTrackProjection,
        with artworkID: UUID
    ) -> LibraryTrackProjection {
        LibraryTrackProjection(
            id: track.id,
            title: track.title,
            artistID: track.artistID,
            artist: track.artist,
            albumID: track.albumID,
            album: track.album,
            duration: track.duration,
            year: track.year,
            codec: track.codec,
            sampleRate: track.sampleRate,
            channelCount: track.channelCount,
            bitDepth: track.bitDepth,
            isFavorite: track.isFavorite,
            isExplicit: track.isExplicit,
            customArtworkID: artworkID,
            artworkID: artworkID,
            relativeMediaPath: track.relativeMediaPath,
            lastPlayedAt: track.lastPlayedAt,
            hasSynchronizedLyrics: track.hasSynchronizedLyrics
        )
    }

    func togglingFavorite(
        _ track: LibraryTrackProjection
    ) -> LibraryTrackProjection {
        replacing(
            track,
            title: track.title,
            isFavorite: !track.isFavorite
        )
    }

    func replacingTitle(
        _ track: LibraryTrackProjection,
        with title: String
    ) -> LibraryTrackProjection {
        replacing(
            track,
            title: title,
            isFavorite: track.isFavorite
        )
    }

    func replacing(
        _ track: LibraryTrackProjection,
        title: String,
        isFavorite: Bool
    ) -> LibraryTrackProjection {
        LibraryTrackProjection(
            id: track.id,
            title: title,
            artistID: track.artistID,
            artist: track.artist,
            albumID: track.albumID,
            album: track.album,
            duration: track.duration,
            year: track.year,
            codec: track.codec,
            sampleRate: track.sampleRate,
            channelCount: track.channelCount,
            bitDepth: track.bitDepth,
            isFavorite: isFavorite,
            isExplicit: track.isExplicit,
            customArtworkID: track.customArtworkID,
            artworkID: track.artworkID,
            relativeMediaPath: track.relativeMediaPath,
            lastPlayedAt: track.lastPlayedAt,
            hasSynchronizedLyrics: track.hasSynchronizedLyrics
        )
    }

    func deterministicUUID(_ index: Int) -> UUID {
        guard
            let id = UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    index + 1
                )
            )
        else {
            preconditionFailure("The deterministic UUID fixture is invalid")
        }
        return id
    }

    var titleSort: TrackTableSortDescriptor {
        TrackTableSortDescriptor(
            field: .song,
            direction: .ascending
        )
    }

    var presentation: TrackTablePresentationKey {
        presentationWithSongWidth(360)
    }

    func presentationWithSongWidth(
        _ songWidth: Double
    ) -> TrackTablePresentationKey {
        TrackTablePresentationKey(
            modelID: ObjectIdentifier(presentationModel),
            context: .library,
            columns: [],
            widths: TrackTableResolvedWidths(
                song: songWidth,
                album: 220,
                year: 72,
                time: 72
            ),
            playlistID: nil,
            queueSource: .allTracks,
            canReorder: false
        )
    }

    func makeCore(
        rows: [LibraryTrackProjection],
        selection: Binding<Set<UUID>>,
        probe: TrackTableWorkProbe?,
        sourceIndex: Int
    ) -> TrackTableCore {
        makeCore(
            rows: rows,
            selection: selection,
            probe: probe,
            version: TrackTableContentVersion(
                sourceID: deterministicUUID(sourceIndex),
                generation: 0
            )
        )
    }

    func makeCore(
        rows: [LibraryTrackProjection],
        selection: Binding<Set<UUID>>,
        probe: TrackTableWorkProbe?,
        version: TrackTableContentVersion
    ) -> TrackTableCore {
        makeCore(
            rows: rows,
            selection: selection,
            probe: probe,
            version: version,
            widths: presentation.widths
        )
    }

    func makeCore(
        rows: [LibraryTrackProjection],
        selection: Binding<Set<UUID>>,
        probe: TrackTableWorkProbe?,
        version: TrackTableContentVersion,
        widths: TrackTableResolvedWidths
    ) -> TrackTableCore {
        makeCore(
            snapshot: makeSnapshot(
                rows: rows,
                version: version
            ),
            selection: selection,
            probe: probe,
            widths: widths
        )
    }

    func makeCore(
        snapshot: TrackTableProjectionSnapshot,
        selection: Binding<Set<UUID>>,
        probe: TrackTableWorkProbe?,
        widths: TrackTableResolvedWidths
    ) -> TrackTableCore {
        TrackTableCore(
            model: presentationModel,
            context: .library,
            snapshot: snapshot,
            virtualWindow: nil,
            columns: [],
            widths: widths,
            playlistID: nil,
            queueSource: .allTracks,
            reorderAction: nil,
            onReachEnd: nil,
            renderer: .hosted,
            workProbe: probe,
            selection: selection
        )
    }

    func makeVirtualCore(
        window: LibraryTrackWindow,
        selection: Binding<Set<UUID>>,
        probe: TrackTableWorkProbe?
    ) -> TrackTableCore {
        TrackTableCore(
            model: presentationModel,
            context: .library,
            snapshot: nil,
            virtualWindow: window,
            columns: [],
            widths: presentation.widths,
            playlistID: nil,
            queueSource: .allTracks,
            reorderAction: nil,
            onReachEnd: nil,
            renderer: .hosted,
            workProbe: probe,
            selection: selection
        )
    }

    func rowConfiguration(
        _ track: LibraryTrackProjection,
        isSelected: Bool,
        artworkLoader: (@MainActor @Sendable (
            UUID,
            ArtworkAssetVariant
        ) async -> ArtworkAsset?)? = nil,
        artworkWorkProbe: ProductionArtworkWorkProbe? = nil
    ) -> TrackTableRowConfiguration {
        TrackTableRowConfiguration(
            model: presentationModel,
            track: track,
            queueIDProvider: TrackTableQueueIDProvider(
                snapshot: makeSnapshot(
                    rows: [track],
                    version: TrackTableContentVersion(
                        sourceID: deterministicUUID(50006),
                        generation: 0
                    )
                )
            ),
            columns: [],
            widths: presentation.widths,
            playlistID: nil,
            queueSource: .allTracks,
            reorderAction: nil,
            resolveDraggedTrackIDs: { $0 },
            actionTrackIDs: [track.id],
            isSelected: isSelected,
            isFocused: isSelected,
            artworkLoader: artworkLoader,
            artworkWorkProbe: artworkWorkProbe,
            select: {}
        )
    }

    func makeSnapshot(
        rows: [LibraryTrackProjection],
        version: TrackTableContentVersion
    ) -> TrackTableProjectionSnapshot {
        TrackTableProjectionSnapshot(
            identity: TrackTableProjectionIdentity(
                contentVersion: version,
                localSort: nil
            ),
            rows: rows,
            orderedIDs: rows.map(\.id),
            indexByID: Dictionary(
                uniqueKeysWithValues: rows.enumerated().map {
                    ($0.element.id, $0.offset)
                }
            )
        )
    }
}

@MainActor
final class SuspendedTrackArtworkLoader {
    private var continuations: [
        UUID: [CheckedContinuation<ArtworkAsset?, Never>]
    ] = [:]
    private var cancellations: [UUID: Bool] = [:]
    private(set) var startedArtworkIDs: [UUID] = []

    func load(
        artworkID: UUID,
        variant _: ArtworkAssetVariant
    ) async -> ArtworkAsset? {
        startedArtworkIDs.append(artworkID)
        let asset = await withCheckedContinuation { continuation in
            continuations[artworkID, default: []].append(continuation)
        }
        cancellations[artworkID] = Task.isCancelled
        return asset
    }

    func hasStarted(_ artworkID: UUID) -> Bool {
        startedArtworkIDs.contains(artworkID)
    }

    func observedCancellation(for artworkID: UUID) -> Bool? {
        cancellations[artworkID]
    }

    func release(
        _ artworkID: UUID,
        asset: ArtworkAsset?
    ) {
        continuations.removeValue(forKey: artworkID)?
            .forEach { $0.resume(returning: asset) }
    }

    func releaseAll() {
        let pending = continuations.values.flatMap(\.self)
        continuations.removeAll()
        pending.forEach { $0.resume(returning: nil) }
    }
}

final class WeakObjectBox {
    weak var value: AnyObject?

    init(_ value: AnyObject) {
        self.value = value
    }
}

@MainActor
final class RecordingTrackTableView: NSTableView {
    var recordedVisibleRows: NSRange
    private(set) var reloadedRowSets: [IndexSet] = []
    var reusableViews: [NSView] = []
    var reloadHandler: ((IndexSet) -> Void)?

    init(visibleRows: NSRange) {
        recordedVisibleRows = visibleRows
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func rows(in _: NSRect) -> NSRange {
        recordedVisibleRows
    }

    override func makeView(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        owner: Any?
    ) -> NSView? {
        guard !reusableViews.isEmpty else {
            return super.makeView(withIdentifier: identifier, owner: owner)
        }
        return reusableViews.removeFirst()
    }

    override func reloadData(
        forRowIndexes rowIndexes: IndexSet,
        columnIndexes _: IndexSet
    ) {
        reloadedRowSets.append(rowIndexes)
        reloadHandler?(rowIndexes)
    }
}

@MainActor
final class ScrollLifecycleRecordingTrackTableView: NSTableView {
    private let recordedVisibleRows: NSRange?
    private(set) var frameSizeWrites = 0

    init(
        frame frameRect: NSRect,
        visibleRows: NSRange? = nil
    ) {
        recordedVisibleRows = visibleRows
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func rows(in rect: NSRect) -> NSRange {
        recordedVisibleRows ?? super.rows(in: rect)
    }

    override func setFrameSize(_ newSize: NSSize) {
        frameSizeWrites += 1
        super.setFrameSize(newSize)
    }

    func resetFrameSizeWrites() {
        frameSizeWrites = 0
    }
}

enum TrackWindowSourceError: Error {
    case intentionalFailure
}

@MainActor
final class SuspendedFlingTrackWindowSource {
    private let rows: [LibraryTrackProjection]
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var startWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var startedOffsets: Set<Int> = []
    private var cancellations: [Int: Bool] = [:]

    init(rows: [LibraryTrackProjection]) {
        self.rows = rows
    }

    func rows(
        offset: Int,
        limit: Int
    ) async -> [LibraryTrackProjection] {
        guard offset > 0 else {
            return Array(rows.prefix(limit))
        }
        startedOffsets.insert(offset)
        startWaiters.removeValue(forKey: offset)?
            .forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            continuations[offset] = continuation
        }
        cancellations[offset] = Task.isCancelled
        guard offset < rows.count else {
            return []
        }
        return Array(rows[offset ..< min(offset + limit, rows.count)])
    }

    func waitUntilStarted(offset: Int) async {
        guard !startedOffsets.contains(offset) else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters[offset, default: []].append(continuation)
        }
    }

    func observedCancellation(offset: Int) -> Bool? {
        cancellations[offset]
    }

    func release(offset: Int) {
        continuations.removeValue(forKey: offset)?.resume()
    }

    func releaseAll() {
        let pending = continuations.values
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

actor RetryOnceTrackWindowSource {
    private let rows: [LibraryTrackProjection]
    private let failingOffset: Int
    private var attemptsByOffset: [Int: Int] = [:]

    init(
        rows: [LibraryTrackProjection],
        failingOffset: Int
    ) {
        self.rows = rows
        self.failingOffset = failingOffset
    }

    func rows(
        offset: Int,
        limit: Int
    ) throws -> [LibraryTrackProjection] {
        attemptsByOffset[offset, default: 0] += 1
        if offset == failingOffset, attemptsByOffset[offset] == 1 {
            throw TrackWindowSourceError.intentionalFailure
        }
        guard offset < rows.count else {
            return []
        }
        return Array(rows[offset ..< min(offset + limit, rows.count)])
    }

    func attemptCount(offset: Int) -> Int {
        attemptsByOffset[offset, default: 0]
    }
}

actor OverlappingTrackWindowSource {
    private let initialRows: [LibraryTrackProjection]
    private let suspendedRows: [LibraryTrackProjection]
    private let newestRows: [LibraryTrackProjection]
    private var requestCount = 0
    private var suspendedContinuation:
        CheckedContinuation<[LibraryTrackProjection], Error>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        initialRows: [LibraryTrackProjection],
        suspendedRows: [LibraryTrackProjection],
        newestRows: [LibraryTrackProjection]
    ) {
        self.initialRows = initialRows
        self.suspendedRows = suspendedRows
        self.newestRows = newestRows
    }

    func rows(
        offset _: Int,
        limit _: Int
    ) async throws -> [LibraryTrackProjection] {
        requestCount += 1
        switch requestCount {
        case 1:
            return initialRows
        case 2:
            suspensionWaiters.forEach { $0.resume() }
            suspensionWaiters.removeAll()
            return try await withCheckedThrowingContinuation { continuation in
                suspendedContinuation = continuation
            }
        default:
            return newestRows
        }
    }

    func waitUntilSuspended() async {
        guard suspendedContinuation == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resumeSuspendedRequest() {
        guard let suspendedContinuation else {
            return
        }
        self.suspendedContinuation = nil
        suspendedContinuation.resume(returning: suspendedRows)
    }
}

actor MutableTrackWindowSource {
    private var projections: [LibraryTrackProjection] = []

    func replace(with projections: [LibraryTrackProjection]) {
        self.projections = projections
    }

    func rows(offset: Int, limit: Int) -> [LibraryTrackProjection] {
        guard offset < projections.count else {
            return []
        }
        return Array(
            projections[offset ..< min(offset + limit, projections.count)]
        )
    }
}

enum VirtualSelectionReplacementScenario: CaseIterable, Sendable {
    case repositorySort
    case sameCountSemanticReorder
    case removedTrack
    case changedQuery

    var advancesContentVersion: Bool {
        self == .sameCountSemanticReorder
    }

    func replacement(
        initialRows: [LibraryTrackProjection],
        selectedTrack: LibraryTrackProjection
    ) -> (rows: [LibraryTrackProjection], query: LibraryTrackQuery) {
        switch self {
        case .repositorySort:
            let rows = initialRows.filter { $0.id != selectedTrack.id }
                + [selectedTrack]
            return (
                rows,
                LibraryTrackQuery(
                    sort: LibraryTrackSort(
                        field: .song,
                        direction: .descending
                    )
                )
            )
        case .sameCountSemanticReorder:
            return (
                initialRows.filter { $0.id != selectedTrack.id }
                    + [selectedTrack],
                .allTracks
            )
        case .removedTrack:
            return (
                initialRows.filter { $0.id != selectedTrack.id },
                .allTracks
            )
        case .changedQuery:
            return (
                Array(initialRows.suffix(24)),
                LibraryTrackQuery(search: "filtered")
            )
        }
    }
}

actor TrackWindowLoadCounter {
    private(set) var requests: [Int] = []

    func record(offset: Int, limit _: Int) {
        requests.append(offset)
    }
}

@MainActor
struct VirtualTrackMutationFixture {
    let root: URL
    let location: ManagedLibraryLocation
    let package: ManagedLibraryPackage
    let container: ModelContainer
    let artistID: UUID
    let trackID: UUID
    let image: Data

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Virtual-Track-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        location = ManagedLibraryLocation(musicDirectory: root)
        package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let importID = UUID()
        let artist = ArtistRecord(name: "Virtual Artist")
        let album = AlbumRecord(title: "Virtual Album", artist: artist)
        let track = TrackRecord(
            originalFilename: "Virtual Track.flac",
            title: "Virtual Track",
            duration: 180,
            codec: "FLAC",
            container: "FLAC",
            sampleRate: 48000,
            channelCount: 2,
            contentHash: String(repeating: "a", count: 64),
            relativeMediaPath: "Media/virtual-track.flac",
            importSessionID: importID,
            artist: artist,
            album: album
        )
        let session = ImportSessionRecord(
            id: importID,
            sourceDisplayName: "Virtual Fixture",
            state: .complete
        )
        context.insert(artist)
        context.insert(album)
        context.insert(track)
        context.insert(session)
        try context.save()
        artistID = artist.id
        trackID = track.id
        image = try #require(
            Data(
                base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAA"
                    + "C0lEQVR42mP8/x8AAusB9WlRkwAAAABJRU5ErkJggg=="
            )
        )
    }

    func artworkRequest(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID
    ) -> ManagedArtworkEditRequest {
        ManagedArtworkEditRequest(
            ownerKind: ownerKind,
            ownerID: ownerID,
            data: image,
            scale: 1,
            normalizedOffset: .zero
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
