@testable import Cadence
import Foundation
import Testing

@MainActor
struct ArtistsListeningAppModelTests {
    @Test("Artists start at overview with independent favorite state")
    func initialState() throws {
        let model = CadenceAppModel.preview(
            favoriteAlbumDates: [:],
            favoriteArtistDates: ["North Assembly": .distantPast]
        )
        let artist = try #require(
            model.artists.first { $0.id == "North Assembly" }
        )

        #expect(model.artistsPresentation == .overview)
        #expect(model.allArtistsSortDescriptor == .allArtists)
        #expect(model.isFavorite(artist))
        #expect(
            model.albumsForArtist(artist.id)
                .allSatisfy { !model.isFavorite($0) }
        )
    }

    @Test("Artist favorite commands are idempotent and ignore stale artists")
    func favoriteCommands() throws {
        let model = CadenceAppModel.preview(favoriteArtistDates: [:])
        let artist = try #require(model.artists.first)
        let timestamp = Date(timeIntervalSince1970: 123)

        model.setArtistFavorite(artist, isFavorite: true, at: timestamp)
        model.setArtistFavorite(artist, isFavorite: true, at: .distantFuture)

        #expect(model.favoriteArtistDates == [artist.id: timestamp])

        let stale = ArtistPreview(
            id: "missing",
            name: "Missing",
            albumCount: 0,
            trackCount: 0
        )
        model.setArtistFavorite(stale, isFavorite: true)
        #expect(model.favoriteArtistDates["missing"] == nil)
    }

    @Test("Artists routing retains origin, sorting, and search")
    func routing() throws {
        let model = CadenceAppModel.preview()
        let artist = try #require(model.artists.first)
        model.activateAllArtistsSort(.trackCount)
        model.artistSearchQuery = artist.name

        model.requestOpenArtist(artist, origin: .search)

        #expect(model.presentedArtist?.id == artist.id)
        #expect(!model.shouldPresentArtistSearchResults)
        #expect(model.selectedArtistID == artist.id)
        #expect(
            model.selectedTrackID == model.canonicalTracks(for: artist).first?.id
        )

        model.requestArtistsBack()

        #expect(model.artistsPresentation == .overview)
        #expect(model.shouldPresentArtistSearchResults)
        #expect(model.artistSearchQuery == artist.name)
        #expect(model.allArtistsSortDescriptor.field == .trackCount)
    }

    @Test("Artist derived tags include effective accepted tags")
    func derivedTags() throws {
        let model = CadenceAppModel.preview()
        let artist = try #require(
            model.artists.first { $0.id == "North Assembly" }
        )
        let tagIDs = model.derivedTags(for: artist).map(\.id)

        #expect(tagIDs.contains("context/night"))
        #expect(!tagIDs.contains("mood/sad"))
    }

    @Test("Custom artist image can be replaced and removed in memory")
    func customImage() throws {
        let model = CadenceAppModel.preview()
        let artist = try #require(model.artists.first)
        let first = ArtistImageAsset(data: Data([1, 2, 3]))
        let second = ArtistImageAsset(
            data: Data([4, 5, 6]),
            scale: 2,
            normalizedOffset: CGSize(width: 0.1, height: -0.2)
        )

        model.setCustomImage(first, for: artist)
        model.setCustomImage(second, for: artist)

        #expect(model.customArtistImages[artist.id] == second)

        model.removeCustomImage(for: artist)
        #expect(model.customArtistImages[artist.id] == nil)
    }

    @Test("Artist playback remains a stable canonical snapshot")
    func playbackSnapshot() throws {
        let model = CadenceAppModel.preview(favoriteArtistDates: [:])
        let artist = try #require(
            model.artists.first { $0.id == "North Assembly" }
        )
        let expected = model.canonicalTracks(for: artist).map(\.id)

        #expect(model.playArtist(artist))
        let snapshot = model.activePlaybackQueue?.orderedTrackIDs
        model.toggleFavorite(artist, at: .now)
        model.activateAllArtistsSort(.recentlyPlayed)
        model.artistSearchQuery = "nothing"
        model.removeCustomImage(for: artist)

        #expect(snapshot == expected)
        #expect(model.activePlaybackQueue?.source == .artist(artist.id))
        #expect(model.activePlaybackQueue?.orderedTrackIDs == expected)
    }

    @Test("Album detail opened from Artists returns to the exact artist origin")
    func albumReturn() throws {
        let model = CadenceAppModel.preview()
        let artist = try #require(
            model.artists.first { $0.id == "North Assembly" }
        )
        let album = try #require(model.albumsForArtist(artist.id).first)
        model.artistSearchQuery = "north"
        model.requestOpenArtist(artist, origin: .search)

        model.requestOpenAlbum(album, origin: .artist(artist.id))

        #expect(model.selectedDestination == .albums)
        #expect(model.presentedAlbum?.id == album.id)

        model.requestAlbumsBack()

        #expect(model.selectedDestination == .artists)
        #expect(model.presentedArtist?.id == artist.id)
        #expect(
            model.artistsPresentation == .detail(
                artist.id,
                origin: .search
            )
        )

        model.requestArtistsBack()

        #expect(model.artistsPresentation == .overview)
        #expect(model.artistSearchQuery == "north")
    }
}
