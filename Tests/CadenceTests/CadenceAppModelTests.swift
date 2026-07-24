@testable import Cadence
import Testing

@MainActor
struct CadenceAppModelTests {
    @Test("Search matches track metadata and tags")
    func search() {
        let model = CadenceAppModel()

        model.searchScope = .library
        model.searchQuery = "After the Rain"

        #expect(model.visibleTracks.map(\.title) == ["After the Rain"])
    }

    @Test("Artist and album selection update the browsing chain")
    func browsingChain() throws {
        let model = CadenceAppModel()
        let artist = try #require(model.artists.first { $0.name == "Mara Vale" })

        model.selectArtist(artist)

        #expect(model.selectedArtist?.name == "Mara Vale")
        #expect(model.selectedAlbum?.title == "Quiet Machines")
        #expect(model.selectedTrack?.artist == "Mara Vale")
        #expect(model.visibleTracks.allSatisfy { $0.album == "Quiet Machines" })
    }

    @Test("Artist selection preserves canonical artist order")
    func artistSelectionPreservesOrder() throws {
        let model = CadenceAppModel()
        let originalOrder = model.artists.map(\.id)
        let artist = try #require(model.artists.last)

        model.selectArtist(artist)

        #expect(model.artists.map(\.id) == originalOrder)
        #expect(model.selectedArtistID == artist.id)
    }

    @Test("Album selection preserves canonical album order")
    func albumSelectionPreservesOrder() throws {
        let model = CadenceAppModel()
        let artist = try #require(model.artists.first { $0.name == "North Assembly" })
        model.selectArtist(artist)
        let originalOrder = model.albumsForSelectedArtist.map(\.id)
        let album = try #require(model.albumsForSelectedArtist.last)

        model.selectAlbum(album)

        #expect(model.albumsForSelectedArtist.map(\.id) == originalOrder)
        #expect(model.selectedAlbumID == album.id)
    }

    @Test("Playing a selected track updates mock transport state")
    func playSelection() throws {
        let model = CadenceAppModel()
        let track = try #require(model.tracks.dropFirst().first)

        model.play(track)

        #expect(model.currentTrackID == track.id)
        #expect(model.selectedTrackID == track.id)
        #expect(model.isPlaying)
        #expect(model.progress == 0)
    }

    @Test("Next and previous wrap through the library")
    func transportWraps() throws {
        let model = CadenceAppModel()
        let first = try #require(model.tracks.first)
        let last = try #require(model.selectedAlbumTracks.last)

        model.selectPreviousTrack()
        #expect(model.currentTrackID == last.id)

        model.selectNextTrack()
        #expect(model.currentTrackID == first.id)
    }

    @Test("Favorite state can be changed without mutating preview data")
    func favoriteState() throws {
        let model = CadenceAppModel()
        let track = try #require(model.tracks.first)
        let originalState = model.isFavorite(track)

        model.toggleFavorite(track)

        #expect(model.isFavorite(track) != originalState)
    }

    @Test("Album years never use thousands separators")
    func albumYearFormatting() throws {
        let model = CadenceAppModel()
        let album = try #require(model.albums.first { $0.title == "Pale Signals" })

        #expect(album.yearText == "2024")
    }

    @Test("Track preview metadata belongs to the exact selected track")
    func trackPreviewMetadata() throws {
        let model = CadenceAppModel()
        let track = try #require(model.tracks.first { $0.id == 17 })

        #expect(
            track.libraryPreviewMetadataText
                == "Transient Lines · 2026 · 4:55 · FLAC"
        )
    }
}
