@testable import Cadence
import Foundation
import Testing

@MainActor
struct AlbumsListeningAppModelTests {
    @Test("Albums start at overview with independent favorite state")
    func initialState() throws {
        let favoriteID = "Mara Vale\u{1F}Quiet Machines"
        let model = CadenceAppModel.testFixture(
            favoriteAlbumDates: [favoriteID: .distantPast]
        )
        let favorite = try #require(
            model.favoriteAlbums.first { $0.id == favoriteID }
        )

        #expect(model.albumsPresentation == .overview)
        #expect(model.allAlbumsSortDescriptor == .allAlbums)
        #expect(model.isFavorite(favorite))
        #expect(
            model.tracks
                .filter { $0.albumID == favorite.id }
                .allSatisfy { !model.isFavorite($0) }
        )
    }

    @Test("Favorite commands are idempotent and ignore stale albums")
    func favoriteCommands() throws {
        let model = CadenceAppModel.testFixture(favoriteAlbumDates: [:])
        let album = try #require(model.albums.first)
        let timestamp = Date(timeIntervalSince1970: 123)

        model.setAlbumFavorite(album, isFavorite: true, at: timestamp)
        model.setAlbumFavorite(album, isFavorite: true, at: .distantFuture)

        #expect(model.favoriteAlbumDates == [album.id: timestamp])

        let stale = AlbumPreview(
            id: "missing",
            title: "Missing",
            artist: "Nobody",
            year: 2026,
            dateAdded: .now,
            trackCount: 0,
            totalDuration: 0,
            artworkPalette: .silver,
            genres: []
        )
        model.setAlbumFavorite(stale, isFavorite: true)
        #expect(model.favoriteAlbumDates["missing"] == nil)
    }

    @Test("Albums routing retains origin, sorting, and search")
    func routing() throws {
        let model = CadenceAppModel.testFixture()
        let album = try #require(model.albums.first)
        model.activateAllAlbumsSort(.title)
        model.albumSearchQuery = album.title

        model.requestOpenAlbum(album, origin: .search)

        #expect(model.presentedAlbum?.id == album.id)
        #expect(!model.shouldPresentAlbumSearchResults)
        #expect(model.selectedAlbumID == album.id)
        #expect(model.selectedTrackID == model.selectedAlbumTracks.first?.id)

        model.requestAlbumsBack()

        #expect(model.albumsPresentation == .overview)
        #expect(model.shouldPresentAlbumSearchResults)
        #expect(model.albumSearchQuery == album.title)
        #expect(model.allAlbumsSortDescriptor.field == .title)
    }

    @Test("Album tags describe direct, inherited, and excluded states")
    func albumTags() throws {
        let model = CadenceAppModel.testFixture()
        let album = try #require(
            model.albums.first { $0.title == "Signals After Dark" }
        )
        let excludedTrack = try #require(model.tracks.first { $0.id == 9 })

        #expect(model.assignedTags(for: album).map(\.id).contains("context/night"))
        #expect(
            model.trackTagItems(for: excludedTrack).contains {
                $0.tag.id == "context/night" && $0.source == .excluded
            }
        )
    }

    @Test("Album playback remains a stable canonical snapshot")
    func playbackSnapshot() throws {
        let model = CadenceAppModel.testFixture(favoriteAlbumDates: [:])
        let album = try #require(
            model.albums.first { $0.title == "Signals After Dark" }
        )
        let expected = model.tracks
            .filter { $0.albumID == album.id }
            .sorted { $0.trackNumber < $1.trackNumber }
            .map(\.id)

        #expect(model.playAlbum(album))
        let snapshot = model.activePlaybackQueue?.orderedTrackIDs
        model.toggleFavorite(album, at: .now)
        model.activateAllAlbumsSort(.releaseYear)
        model.albumSearchQuery = "nothing"

        #expect(snapshot == expected)
        #expect(model.activePlaybackQueue?.orderedTrackIDs == expected)
    }
}
