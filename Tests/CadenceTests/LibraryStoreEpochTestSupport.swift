@testable import Cadence
import Foundation
import SwiftData

enum LibraryEpochTestError: Error, Sendable {
    case cacheReload
    case staleOperation
}

func makeEpochDummyPackage(label: String) -> ManagedLibraryPackage {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "Cadence-Epoch-\(label)-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    return ManagedLibraryPackage(
        location: ManagedLibraryLocation(musicDirectory: root)
    )
}

func makeInitialEpochSnapshot(
    from repository: LibraryRepository
) async throws -> InitialLibrarySnapshot {
    async let tracks = repository.tracksPage()
    async let favoriteTracks = repository.favoriteTracksPage()
    async let favoriteTrackIDs = repository.favoriteTrackIDs()
    async let recentlyPlayedTracks = repository.recentlyPlayedTracks()
    async let artists = repository.artistsPage()
    async let favoriteArtists = repository.favoriteArtistsPage()
    async let albums = repository.albumsPage()
    async let favoriteAlbums = repository.favoriteAlbumsPage()
    async let tags = repository.tagsPage()
    async let counts = repository.catalogCounts()
    async let trashOperations = repository.trashOperations(location: nil)
    return try await InitialLibrarySnapshot(
        tracks: tracks,
        favoriteTracks: favoriteTracks,
        favoriteTrackIDs: favoriteTrackIDs,
        recentlyPlayedTracks: recentlyPlayedTracks,
        artists: artists,
        favoriteArtists: favoriteArtists,
        albums: albums,
        favoriteAlbums: favoriteAlbums,
        tags: tags,
        counts: counts,
        trashOperations: trashOperations
    )
}

actor LibraryEpochResultGate<Value: Sendable> {
    private let value: Value
    private var continuation: CheckedContinuation<Value, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var isSuspended = false

    init(_ value: Value) {
        self.value = value
    }

    func suspend() async -> Value {
        isSuspended = true
        suspensionWaiters.forEach { $0.resume() }
        suspensionWaiters.removeAll()
        return await withCheckedContinuation { continuation in
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
        continuation?.resume(returning: value)
        continuation = nil
    }
}

struct LibraryEpochFixture {
    let container: ModelContainer
    let repository: LibraryRepository
    let trackID: UUID

    init(
        title: String,
        lastPlayedAt: Date? = nil,
        trackID: UUID = UUID()
    ) throws {
        container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let importID = UUID()
        let artist = ArtistRecord(name: "\(title) Artist")
        let album = AlbumRecord(title: "\(title) Album", artist: artist)
        let session = ImportSessionRecord(
            id: importID,
            sourceDisplayName: title,
            state: .complete
        )
        let track = TrackRecord(
            id: trackID,
            originalFilename: "\(title).flac",
            title: title,
            duration: 180,
            codec: "FLAC",
            container: "FLAC",
            sampleRate: 48000,
            channelCount: 2,
            contentHash: String(repeating: "a", count: 64),
            relativeMediaPath: "Media/\(trackID.uuidString).flac",
            importSessionID: importID,
            artist: artist,
            album: album
        )
        track.lastPlayedAt = lastPlayedAt

        context.insert(artist)
        context.insert(album)
        context.insert(session)
        context.insert(track)
        try context.save()

        repository = LibraryRepository(modelContainer: container)
        self.trackID = trackID
    }
}
