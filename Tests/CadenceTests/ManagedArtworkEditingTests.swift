@testable import Cadence
import Foundation
import SwiftData
import Testing

struct ManagedArtworkEditingTests {
    @Test("Managed artwork replacement persists one current asset")
    func replaceAndRemoveArtwork() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }

        let firstResult = try await fixture.service.setArtwork(
            fixture.request(scale: 1.25)
        )
        let firstID = try #require(firstResult.primaryArtworkID)
        let first = try #require(
            try await fixture.repository.artwork(id: firstID)
        )
        #expect(try fixture.location.resolve(relativePath: first.relativePath).exists)
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == firstID
        )

        let replacementResult = try await fixture.service.setArtwork(
            fixture.request(scale: 1)
        )
        let replacementID = try #require(replacementResult.primaryArtworkID)
        #expect(replacementID != firstID)
        #expect(!fixture.package.packageURL.appending(path: first.relativePath).exists)
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == replacementID
        )

        try await fixture.service.removeArtwork(
            ownerKind: .album,
            ownerID: fixture.albumID
        )
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == nil
        )
    }

    @Test("Playlist and Smart Collection artwork use the managed edit pipeline")
    func collectionOwnerParity() async throws {
        for ownerKind in [
            ArtworkOwnerKind.playlist,
            ArtworkOwnerKind.smartCollection,
        ] {
            let fixture = try ManagedArtworkFixture()
            defer { fixture.remove() }
            let ownerID = try #require(fixture.ownerID(for: ownerKind))

            let result = try await fixture.service.setArtwork(
                fixture.request(ownerKind: ownerKind, ownerID: ownerID)
            )
            let artworkID = try #require(result.primaryArtworkID)
            #expect(
                try await fixture.repository.artworkEditSnapshot(
                    ownerKind: ownerKind,
                    ownerID: ownerID
                )?.id == artworkID
            )

            try await fixture.service.removeArtwork(
                ownerKind: ownerKind,
                ownerID: ownerID
            )
            #expect(
                try await fixture.repository.artworkEditSnapshot(
                    ownerKind: ownerKind,
                    ownerID: ownerID
                ) == nil
            )
        }
    }
}

struct ManagedArtworkRecoveryTests {
    @Test("Recovery commits an installed artwork file idempotently")
    func recoversInstalledArtwork() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let manifest = try fixture.manifest(state: .fileInstalled)
        try fixture.installNewFile(for: manifest)
        try fixture.store.save(manifest)

        let first = try await fixture.service.recover()
        let second = try await fixture.service.recover()

        #expect(first.recoveredOperationIDs == [manifest.operationID])
        #expect(second == .empty)
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == manifest.newArtwork?.id
        )
    }

    @Test("Prepared recovery removes staged work and preserves metadata")
    func preparedRecoveryRollsBack() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let manifest = try fixture.manifest(state: .prepared)
        try fixture.store.save(manifest)
        try fixture.image.write(
            to: fixture.store.stagedURL(manifest.operationID)
        )

        let result = try await fixture.service.recover()

        #expect(result.rolledBackOperationIDs == [manifest.operationID])
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == nil
        )
        #expect(!fixture.store.operationURL(manifest.operationID).exists)
    }

    @Test("Committed recovery cleans the previous artwork file")
    func committedRecoveryCleansPreviousFile() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let previousResult = try await fixture.service.setArtwork(
            fixture.request(scale: 1)
        )
        let previousID = try #require(previousResult.primaryArtworkID)
        let previous = try #require(
            try await fixture.repository.artworkEditSnapshot(
                ownerKind: .album,
                ownerID: fixture.albumID
            )
        )
        let previousURL = try fixture.location.resolve(
            relativePath: previous.relativeOriginalPath
        )
        #expect(previous.id == previousID)
        #expect(previousURL.exists)

        let installed = try fixture.manifest(
            state: .fileInstalled,
            previousArtwork: previous
        )
        try fixture.installNewFile(for: installed)
        try await fixture.repository.applyArtworkEdit(installed)
        let committed = installed.advancing(to: .metadataCommitted)
        try fixture.store.save(committed)

        let result = try await fixture.service.recover()

        #expect(result.recoveredOperationIDs == [committed.operationID])
        #expect(!previousURL.exists)
        #expect(
            try await fixture.repository.album(id: fixture.albumID)?
                .customArtworkID == committed.newArtwork?.id
        )
    }

    @Test("Hash mismatch is quarantined without deleting the unexpected file")
    func hashMismatchIsQuarantined() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let manifest = try fixture.manifest(state: .fileInstalled)
        let target = try #require(manifest.newArtwork).relativeOriginalPath
        let targetURL = try fixture.location.resolve(relativePath: target)
        try Data("unexpected".utf8).write(to: targetURL)
        try fixture.store.save(manifest)

        await #expect(throws: ManagedArtworkEditError.self) {
            try await fixture.service.recover()
        }

        #expect(try Data(contentsOf: targetURL) == Data("unexpected".utf8))
        #expect(
            fixture.store.quarantineRootURL.appending(
                path: manifest.operationID.uuidString
            ).exists
        )
    }
}

@MainActor
// Publication scenarios share one expensive managed-library fixture and lifecycle.
// swiftlint:disable:next type_body_length
struct ManagedArtworkPublicationTests {
    @Test("Album artwork patches every resident projection without resetting descriptors")
    func albumArtworkMutationPublishesEveryResidentProjectionWithoutResettingDescriptors() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let store = LibraryStore(
            container: fixture.container,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        await store.loadPlaylists()
        let track = try #require(store.tracks.first)
        let album = try #require(store.albums.first)
        let query = LibraryTrackQuery(
            search: "artwork",
            sort: LibraryTrackSort(field: .duration, direction: .descending)
        )
        let cursor = LibraryPageCursor.offset(17)
        let searchCursor = LibraryPageCursor.offset(23)
        let rule = SmartCollectionRuleGroup(combinator: .all, children: [])
        let lyricsMatch = LyricsSearchMatch(
            trackID: track.id,
            lineIndex: 4,
            timestamp: 12,
            snippet: "resident artwork"
        )
        store.trackQuery = query
        store.trackCursor = cursor
        store.favoriteTracks = [track]
        store.recentlyPlayedTracks = [track]
        store.browserTracks = [track]
        store.browserTrackCursor = cursor
        store.selectedPlaylistID = fixture.playlistID
        store.selectedPlaylistTracks = [track]
        store.playbackQueueTracks = [
            PlaybackQueueTrackProjection(id: track.id, state: .available(track)),
        ]
        store.favoriteAlbums = [album]
        store.browserAlbums = [album]
        store.browserAlbumCursor = cursor
        store.catalogSearchResults = CatalogSearchResults(
            tracks: [track],
            albums: [album],
            artists: [],
            tags: [],
            lyrics: [LyricsCatalogSearchResult(track: track, match: lyricsMatch)],
            trackCursor: searchCursor,
            albumCursor: searchCursor,
            artistCursor: nil,
            tagCursor: nil
        )
        store.smartCollectionResults[rule] = ProductionSmartCollectionStoreResult(
            evaluation: ProductionSmartCollectionEvaluation(
                orderedTrackIDs: [track.id],
                totalDuration: track.duration
            ),
            tracks: [track],
            nextOffset: 31,
            contentVersion: TrackTableContentVersion(
                sourceID: UUID(),
                generation: 7
            )
        )
        let window = try #require(store.allTracksWindow)
        await configure(window, store: store)

        let result = try await store.setArtwork(
            fixture.request(ownerKind: .album, ownerID: album.id),
            location: fixture.location
        )
        let artworkID = try #require(result.primaryArtworkID)
        await configure(window, store: store)

        #expect(store.trackQuery == query)
        #expect(store.trackCursor == cursor)
        #expect(store.browserTrackCursor == cursor)
        #expect(store.browserAlbumCursor == cursor)
        #expect(store.catalogSearchResults.trackCursor == searchCursor)
        #expect(store.catalogSearchResults.albumCursor == searchCursor)
        #expect(store.smartCollectionResults[rule]?.nextOffset == 31)
        #expect(store.albums.first?.customArtworkID == artworkID)
        #expect(store.favoriteAlbums.first?.customArtworkID == artworkID)
        #expect(store.browserAlbums.first?.customArtworkID == artworkID)
        #expect(store.catalogSearchResults.albums.first?.customArtworkID == artworkID)
        #expect(store.tracks.first?.artworkID == artworkID)
        #expect(store.favoriteTracks.first?.artworkID == artworkID)
        #expect(store.recentlyPlayedTracks.first?.artworkID == artworkID)
        #expect(store.browserTracks.first?.artworkID == artworkID)
        #expect(store.selectedPlaylistTracks.first?.artworkID == artworkID)
        #expect(store.playbackQueueTracks.first?.track?.artworkID == artworkID)
        #expect(store.catalogSearchResults.tracks.first?.artworkID == artworkID)
        #expect(store.catalogSearchResults.lyrics.first?.track.artworkID == artworkID)
        #expect(store.smartCollectionResults[rule]?.tracks.first?.artworkID == artworkID)
        #expect(window.track(at: 0)?.artworkID == artworkID)
    }

    @Test("Track artwork removal publishes the album fallback everywhere")
    func trackArtworkRemovalPublishesAlbumFallbackEverywhere() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let store = LibraryStore(
            container: fixture.container,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let albumResult = try await store.setArtwork(
            fixture.request(ownerKind: .album, ownerID: fixture.albumID),
            location: fixture.location
        )
        let albumArtworkID = try #require(albumResult.primaryArtworkID)
        let trackResult = try await store.setArtwork(
            fixture.request(ownerKind: .track, ownerID: fixture.trackID),
            location: fixture.location
        )
        let trackArtworkID = try #require(trackResult.primaryArtworkID)
        let track = try #require(store.tracks.first)
        #expect(track.artworkID == trackArtworkID)
        let match = LyricsSearchMatch(
            trackID: track.id,
            lineIndex: 1,
            timestamp: nil,
            snippet: "fallback"
        )
        store.favoriteTracks = [track]
        store.recentlyPlayedTracks = [track]
        store.browserTracks = [track]
        store.selectedPlaylistTracks = [track]
        store.playbackQueueTracks = [
            PlaybackQueueTrackProjection(id: track.id, state: .available(track)),
        ]
        store.catalogSearchResults = CatalogSearchResults(
            tracks: [track],
            albums: [],
            artists: [],
            tags: [],
            lyrics: [LyricsCatalogSearchResult(track: track, match: match)],
            trackCursor: nil,
            albumCursor: nil,
            artistCursor: nil,
            tagCursor: nil
        )

        _ = try await store.removeArtwork(
            ownerKind: .track,
            ownerID: track.id,
            location: fixture.location
        )

        #expect(store.tracks.first?.artworkID == albumArtworkID)
        #expect(store.favoriteTracks.first?.artworkID == albumArtworkID)
        #expect(store.recentlyPlayedTracks.first?.artworkID == albumArtworkID)
        #expect(store.browserTracks.first?.artworkID == albumArtworkID)
        #expect(store.selectedPlaylistTracks.first?.artworkID == albumArtworkID)
        #expect(store.playbackQueueTracks.first?.track?.artworkID == albumArtworkID)
        #expect(store.catalogSearchResults.tracks.first?.artworkID == albumArtworkID)
        #expect(store.catalogSearchResults.lyrics.first?.track.artworkID == albumArtworkID)
    }

    @Test("Artist artwork patches favorites and active search without reloading")
    func artistArtworkMutationPublishesFavoriteAndSearchProjection() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let store = LibraryStore(
            container: fixture.container,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let artist = try #require(store.artists.first)
        let cursor = LibraryPageCursor.offset(11)
        store.artistCursor = cursor
        store.favoriteArtists = [artist]
        store.catalogSearchResults = CatalogSearchResults(
            tracks: [],
            albums: [],
            artists: [artist],
            tags: [],
            lyrics: [],
            trackCursor: nil,
            albumCursor: nil,
            artistCursor: cursor,
            tagCursor: nil
        )

        let result = try await store.setArtwork(
            fixture.request(ownerKind: .artist, ownerID: artist.id),
            location: fixture.location
        )
        let artworkID = try #require(result.primaryArtworkID)

        #expect(store.artistCursor == cursor)
        #expect(store.catalogSearchResults.artistCursor == cursor)
        #expect(store.artists.first?.customArtworkID == artworkID)
        #expect(store.favoriteArtists.first?.customArtworkID == artworkID)
        #expect(store.catalogSearchResults.artists.first?.customArtworkID == artworkID)
    }

    @Test("Artwork publication retires a suspended search without resetting it")
    func artworkPublicationRetiresSuspendedSearch() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let store = LibraryStore(
            container: fixture.container,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let track = try #require(store.tracks.first)
        let album = try #require(store.albums.first)
        let query = "  Artwork  "
        let cursor = LibraryPageCursor.offset(29)
        store.catalogSearchResults = CatalogSearchResults(
            tracks: [track],
            albums: [album],
            artists: [],
            tags: [],
            lyrics: [],
            trackCursor: cursor,
            albumCursor: cursor,
            artistCursor: nil,
            tagCursor: nil
        )
        let staleResults = CatalogSearchResults(
            tracks: [],
            albums: [],
            artists: [],
            tags: [],
            lyrics: [],
            trackCursor: nil,
            albumCursor: nil,
            artistCursor: nil,
            tagCursor: nil
        )
        let gate = LibraryEpochResultGate(staleResults)
        let search = Task { @MainActor in
            await store.searchCatalog(
                query,
                loader: { _, _ in await gate.suspend() }
            )
        }
        await gate.waitUntilSuspended()
        #expect(store.isCatalogSearching)

        let result = try await store.setArtwork(
            fixture.request(ownerKind: .album, ownerID: album.id),
            location: fixture.location
        )
        let artworkID = try #require(result.primaryArtworkID)
        #expect(!store.isCatalogSearching)

        await gate.resume()
        await search.value

        #expect(store.catalogSearchQuery == query)
        #expect(store.catalogSearchResults.trackCursor == cursor)
        #expect(store.catalogSearchResults.albumCursor == cursor)
        #expect(store.catalogSearchResults.tracks.first?.artworkID == artworkID)
        #expect(store.catalogSearchResults.albums.first?.customArtworkID == artworkID)
        #expect(!store.isCatalogSearching)
    }

    @Test("Artwork publication merges resident local snapshots in place")
    func artworkPublicationMergesResidentLocalSnapshots() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let store = LibraryStore(
            container: fixture.container,
            package: fixture.package
        )
        await store.loadInitialLibrary()
        let originalTrack = try #require(store.tracks.first)
        let originalAlbum = try #require(store.albums.first)

        let result = try await store.setArtwork(
            fixture.request(ownerKind: .album, ownerID: originalAlbum.id),
            location: fixture.location
        )
        let artworkID = try #require(result.primaryArtworkID)
        let publication = try #require(store.artworkPublication)
        var localTracks = [originalTrack]
        let localReleases = ArtistReleaseSections(
            singles: [],
            eps: [],
            albums: [originalAlbum],
            appearsOn: []
        )

        let tracksChanged = publication.mergeTracks(into: &localTracks)
        let mergedReleases = publication.mergingAlbums(in: localReleases)

        #expect(tracksChanged)
        #expect(localTracks.map(\.id) == [originalTrack.id])
        #expect(localTracks.first?.artworkID == artworkID)
        #expect(mergedReleases.albums.map(\.id) == [originalAlbum.id])
        #expect(mergedReleases.albums.first?.customArtworkID == artworkID)
    }

    @Test("Recovered album artwork publishes through an unrelated artist edit once")
    func recoveredAlbumPublishesThroughArtistEdit() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let libraryStore = LibraryStore(
            container: fixture.container,
            package: fixture.package
        )
        await libraryStore.loadInitialLibrary()
        try await libraryStore.setArtwork(
            fixture.request(
                ownerKind: .album,
                ownerID: fixture.albumID
            ),
            location: fixture.location
        )
        let previousArtwork = try #require(
            try await fixture.repository.artworkEditSnapshot(
                ownerKind: .album,
                ownerID: fixture.albumID
            )
        )
        _ = await libraryStore.artworkAsset(
            id: previousArtwork.id,
            location: fixture.location
        )
        let window = try #require(libraryStore.allTracksWindow)
        await configure(window, store: libraryStore)
        let revisionBeforeEdit = window.revision
        let manifest = try fixture.manifest(
            state: .fileInstalled,
            previousArtwork: previousArtwork,
            ownerKind: .album,
            ownerID: fixture.albumID
        )
        let recoveredArtwork = try #require(manifest.newArtwork)
        libraryStore.artworkAssetCache.insert(
            ArtworkAsset(
                id: recoveredArtwork.id,
                revision: recoveredArtwork.revision,
                data: fixture.image
            )
        )
        try fixture.installNewFile(for: manifest)
        try fixture.store.save(manifest)

        let mutation = try await libraryStore.setArtwork(
            fixture.request(
                ownerKind: .artist,
                ownerID: fixture.artistID
            ),
            location: fixture.location
        )
        await configure(window, store: libraryStore)

        #expect(mutation.effects.map(\.ownerKind) == [.album, .artist])
        #expect(mutation.effects.map(\.ownerID) == [fixture.albumID, fixture.artistID])
        #expect(window.track(at: 0)?.artworkID == manifest.newArtwork?.id)
        #expect(window.revision == revisionBeforeEdit + 1)
        #expect(
            libraryStore.artworkAssetCache.asset(
                id: previousArtwork.id,
                revision: previousArtwork.revision
            ) == nil
        )
        #expect(
            libraryStore.artworkAssetCache.asset(
                id: recoveredArtwork.id,
                revision: recoveredArtwork.revision
            ) == nil
        )
    }

    @Test("Direct playlist artwork recovery refreshes the cached playlist")
    func directPlaylistRecoveryPublishes() async throws {
        let fixture = try ManagedArtworkFixture()
        defer { fixture.remove() }
        let libraryStore = LibraryStore(
            container: fixture.container,
            package: fixture.package
        )
        await libraryStore.loadInitialLibrary()
        await libraryStore.loadPlaylists()
        #expect(libraryStore.playlists.first?.customArtworkID == nil)
        let manifest = try fixture.manifest(
            state: .fileInstalled,
            ownerKind: .playlist,
            ownerID: fixture.playlistID
        )
        try fixture.installNewFile(for: manifest)
        try fixture.store.save(manifest)

        let recovery = try await libraryStore.recoverArtworkEdits()

        #expect(recovery.recoveredOperationIDs == [manifest.operationID])
        #expect(
            recovery.effects == [
                ManagedArtworkPublicationEffect(
                    ownerKind: .playlist,
                    ownerID: fixture.playlistID,
                    previousArtworkID: nil,
                    newArtworkID: manifest.newArtwork?.id
                ),
            ]
        )
        #expect(
            libraryStore.playlists.first?.customArtworkID
                == manifest.newArtwork?.id
        )
    }

    @Test("A recovered Smart Collection owner is published by another artwork edit")
    func recoveredSmartCollectionPublishesThroughArtistEdit() async throws {
        let fixture = try await ManagedArtworkAppFixture.make()
        defer { fixture.remove() }
        do {
            let session = fixture.openSession()
            await session.store.loadInitialLibrary()
            let model = CadenceAppModel(
                runtimeEnvironment: .production,
                importRuntimeAvailability: .available,
                librarySession: session
            )
            await model.loadPersistedSmartCollections()
            #expect(model.smartCollections.first?.customArtworkID == nil)
            #expect(model.requestEditSelectedSmartCollection())
            model.renameSmartCollectionDraft("Unsaved Publication Draft")
            let selectedID = model.selectedSmartCollectionID
            let draft = model.smartCollectionDraft
            let presentationMode = model.smartCollectionsPresentationMode
            model.smartCollectionSortDescriptors[fixture.smartCollectionID] =
                SmartCollectionSortDescriptor(
                    field: .duration,
                    direction: .descending
                )
            let sortDescriptor = model.smartCollectionSortDescriptors[
                fixture.smartCollectionID
            ]
            let manifest = try fixture.manifest(state: .fileInstalled)
            try fixture.installNewFile(for: manifest)
            try fixture.store.save(manifest)

            model.setCustomArtwork(
                data: fixture.image,
                scale: 1,
                normalizedOffset: .zero,
                for: .managedArtist(fixture.artistID)
            )
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while model.smartCollections.first?.customArtworkID
                != manifest.newArtwork?.id,
                ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }

            #expect(model.artworkRevision == 1)
            #expect(model.selectedSmartCollectionID == selectedID)
            #expect(model.smartCollectionDraft == draft)
            #expect(model.smartCollectionsPresentationMode == presentationMode)
            #expect(
                model.smartCollectionSortDescriptors[fixture.smartCollectionID]
                    == sortDescriptor
            )
            #expect(
                model.smartCollections.first?.customArtworkID
                    == manifest.newArtwork?.id
            )
        }
    }

    private func configure(
        _ window: LibraryTrackWindow,
        store: LibraryStore
    ) async {
        await window.configure(
            totalCount: store.catalogCounts.liveTrackCount,
            query: store.trackQuery,
            contentVersion: store.allTracksWindowContentVersion
        )
    }
}

struct ManagedArtworkFixture {
    let root: URL
    let location: ManagedLibraryLocation
    let package: ManagedLibraryPackage
    let container: ModelContainer
    let repository: LibraryRepository
    let service: ManagedArtworkService
    let store: ManagedArtworkEditManifestStore
    let artistID: UUID
    let albumID: UUID
    let trackID: UUID
    let playlistID: UUID
    let smartCollectionID: UUID
    let image: Data

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Artwork-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        location = ManagedLibraryLocation(musicDirectory: root)
        package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let importID = UUID()
        let artist = ArtistRecord(name: "Artwork Artist")
        let album = AlbumRecord(title: "Artwork Album", artist: artist)
        let track = TrackRecord(
            originalFilename: "Artwork Track.flac",
            title: "Artwork Track",
            duration: 180,
            codec: "FLAC",
            container: "FLAC",
            sampleRate: 48000,
            channelCount: 2,
            contentHash: String(repeating: "a", count: 64),
            relativeMediaPath: "Media/artwork-track.flac",
            importSessionID: importID,
            artist: artist,
            album: album
        )
        let session = ImportSessionRecord(
            id: importID,
            sourceDisplayName: "Artwork Fixture",
            state: .complete
        )
        let playlist = PlaylistRecord(name: "Artwork Playlist")
        let smartCollection = SmartCollectionRecord(
            name: "Artwork Mix",
            ruleData: Data("fixture".utf8),
            sortDescriptorRawValue: "canonical:ascending",
            playbackPreferenceRawValue: "ordered"
        )
        context.insert(artist)
        context.insert(album)
        context.insert(track)
        context.insert(session)
        context.insert(playlist)
        context.insert(smartCollection)
        try context.save()
        artistID = artist.id
        albumID = album.id
        trackID = track.id
        playlistID = playlist.id
        smartCollectionID = smartCollection.id
        repository = LibraryRepository(modelContainer: container)
        service = ManagedArtworkService(
            package: package,
            repository: repository
        )
        store = ManagedArtworkEditManifestStore(package: package)
        image = try #require(
            Data(
                base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAA"
                    + "C0lEQVR42mP8/x8AAusB9WlRkwAAAABJRU5ErkJggg=="
            )
        )
    }

    func request(scale: CGFloat) -> ManagedArtworkEditRequest {
        request(
            ownerKind: .album,
            ownerID: albumID,
            scale: scale
        )
    }

    func request(
        ownerKind: ArtworkOwnerKind,
        ownerID: UUID,
        scale: CGFloat = 1
    ) -> ManagedArtworkEditRequest {
        ManagedArtworkEditRequest(
            ownerKind: ownerKind,
            ownerID: ownerID,
            data: image,
            scale: scale,
            normalizedOffset: .zero
        )
    }

    func ownerID(
        for ownerKind: ArtworkOwnerKind
    ) -> UUID? {
        switch ownerKind {
        case .artist:
            artistID
        case .album:
            albumID
        case .track:
            trackID
        case .playlist:
            playlistID
        case .smartCollection:
            smartCollectionID
        }
    }

    func manifest(
        state: ManagedArtworkEditManifest.State,
        previousArtwork: ManagedArtworkDescriptor? = nil,
        ownerKind: ArtworkOwnerKind = .album,
        ownerID: UUID? = nil,
        operationID: UUID = UUID(),
        artworkID: UUID = UUID()
    ) throws -> ManagedArtworkEditManifest {
        let resolvedOwnerID = try #require(ownerID ?? self.ownerID(for: ownerKind))
        let payload = try #require(
            MetadataReader().artworkPayload(data: image)
        )
        return ManagedArtworkEditManifest(
            operationID: operationID,
            ownerKind: ownerKind,
            ownerID: resolvedOwnerID,
            mutationKind: .set,
            previousArtwork: previousArtwork,
            newArtwork: ManagedArtworkDescriptor(
                id: artworkID,
                ownerKind: ownerKind,
                ownerID: resolvedOwnerID,
                relativeOriginalPath: "Artwork/Original/\(artworkID.uuidString)."
                    + payload.metadata.format,
                relativeThumbnailPath: nil,
                format: payload.metadata.format,
                pixelWidth: payload.metadata.pixelWidth,
                pixelHeight: payload.metadata.pixelHeight,
                cropScale: 1,
                normalizedOffsetX: 0,
                normalizedOffsetY: 0,
                contentHash: payload.metadata.contentHash,
                revision: 0
            ),
            state: state
        )
    }

    func installNewFile(for manifest: ManagedArtworkEditManifest) throws {
        let artwork = try #require(manifest.newArtwork)
        try image.write(
            to: location.resolve(relativePath: artwork.relativeOriginalPath)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private struct ManagedArtworkAppFixture {
    let root: URL
    let localCatalogRoot: URL
    let location: ManagedLibraryLocation
    let package: ManagedLibraryPackage
    let artistID: UUID
    let smartCollectionID: UUID
    let image: Data
    let store: ManagedArtworkEditManifestStore

    static func make() async throws -> ManagedArtworkAppFixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Artwork-App-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let location = ManagedLibraryLocation(musicDirectory: root)
        let package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        let identity = LibraryIdentity()
        try package.writeIdentity(identity)
        let localCatalog = try LocalLibraryCatalogLocation.currentUser(
            identity: identity
        )
        let container = try LibraryContainerFactory.persistent(
            package: package
        )
        let context = ModelContext(container)
        let artist = ArtistRecord(name: "Publication Artist")
        context.insert(artist)
        try context.save()
        let repository = LibraryRepository(modelContainer: container)
        let collection = SmartCollectionPreview(
            name: "Publication Mix",
            rule: SmartCollectionRuleGroup(
                combinator: .all,
                children: [
                    .condition(
                        SmartCollectionRuleCondition(
                            field: .favorite,
                            operator: .is,
                            value: .boolean(true)
                        )
                    ),
                ]
            ),
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        try await repository.saveSmartCollection(collection)
        let image = try #require(
            Data(
                base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAA"
                    + "C0lEQVR42mP8/x8AAusB9WlRkwAAAABJRU5ErkJggg=="
            )
        )
        return ManagedArtworkAppFixture(
            root: root,
            localCatalogRoot: localCatalog.rootURL,
            location: location,
            package: package,
            artistID: artist.id,
            smartCollectionID: collection.id,
            image: image,
            store: ManagedArtworkEditManifestStore(package: package)
        )
    }

    func openSession() -> LibrarySession {
        LibrarySession.startup(location: location)
    }

    func manifest(
        state: ManagedArtworkEditManifest.State
    ) throws -> ManagedArtworkEditManifest {
        let payload = try #require(
            MetadataReader().artworkPayload(data: image)
        )
        let id = UUID()
        return ManagedArtworkEditManifest(
            operationID: UUID(),
            ownerKind: .smartCollection,
            ownerID: smartCollectionID,
            mutationKind: .set,
            previousArtwork: nil,
            newArtwork: ManagedArtworkDescriptor(
                id: id,
                ownerKind: .smartCollection,
                ownerID: smartCollectionID,
                relativeOriginalPath: "Artwork/Original/\(id.uuidString)."
                    + payload.metadata.format,
                relativeThumbnailPath: nil,
                format: payload.metadata.format,
                pixelWidth: payload.metadata.pixelWidth,
                pixelHeight: payload.metadata.pixelHeight,
                cropScale: 1,
                normalizedOffsetX: 0,
                normalizedOffsetY: 0,
                contentHash: payload.metadata.contentHash,
                revision: 0
            ),
            state: state
        )
    }

    func installNewFile(for manifest: ManagedArtworkEditManifest) throws {
        let artwork = try #require(manifest.newArtwork)
        try image.write(
            to: location.resolve(relativePath: artwork.relativeOriginalPath)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: localCatalogRoot)
    }
}

private extension URL {
    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
