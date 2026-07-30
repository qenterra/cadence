@testable import Cadence
import Foundation
import Testing

@MainActor
struct ContextualNavigationTests {
    @Test("Now Playing album link restores exact playback context")
    func nowPlayingRoundTrip() throws {
        let model = CadenceAppModel.preview()
        let track = try #require(model.currentTrack)
        let album = try #require(
            model.albums.first { $0.id == track.albumID }
        )
        model.selectedDestination = .tags
        model.selectedTagID = "genre/ambient"
        model.tagResultScope = .tracks
        #expect(model.presentNowPlaying())
        model.selectNowPlayingPanel(.queue)
        let queue = model.activePlaybackQueue

        model.requestOpenAlbumContextually(album)

        #expect(model.selectedDestination == .albums)
        #expect(model.presentedAlbum?.id == album.id)
        #expect(model.playbackWorkspace == .hidden)
        #expect(model.activePlaybackQueue == queue)

        model.requestAlbumsBack()

        #expect(model.selectedDestination == .tags)
        #expect(model.selectedTagID == "genre/ambient")
        #expect(model.tagResultScope == .tracks)
        #expect(model.playbackWorkspace == .nowPlaying)
        #expect(model.selectedNowPlayingPanel == .queue)
        #expect(model.currentTrackID == track.id)
        #expect(model.activePlaybackQueue == queue)
    }

    @Test("Nested artist and album routes unwind in order")
    func nestedRoutes() throws {
        let model = CadenceAppModel.preview()
        let firstAlbum = try #require(model.albums.first)
        let secondTrack = try #require(
            model.tracks.first { $0.artistID != firstAlbum.artist }
        )
        let secondArtist = try #require(
            model.artists.first { $0.id == secondTrack.artistID }
        )
        model.selectedDestination = .library

        model.requestOpenAlbumContextually(firstAlbum)
        model.requestOpenArtistContextually(secondArtist)

        #expect(model.presentedArtist?.id == secondArtist.id)
        #expect(model.contextualNavigationHistory.count == 2)

        model.requestArtistsBack()
        #expect(model.selectedDestination == .albums)
        #expect(model.presentedAlbum?.id == firstAlbum.id)

        model.requestAlbumsBack()
        #expect(model.selectedDestination == .library)
        #expect(model.contextualNavigationHistory.isEmpty)
    }

    @Test("Tag routes always open the Tracks scope")
    func tagScope() throws {
        let model = CadenceAppModel.preview()
        let tag = try #require(model.tags.first)
        model.tagResultScope = .albums
        #expect(model.presentNowPlaying())

        model.requestOpenTagContextually(tag)

        #expect(model.selectedDestination == .tags)
        #expect(model.selectedTagID == tag.id)
        #expect(model.selectedTagGroupID == tag.groupID)
        #expect(model.tagResultScope == .tracks)
        #expect(model.hasContextualBackNavigation)
        #expect(model.contextualBackTitle == "Now Playing")
    }

    @Test("Invalid contextual targets are ignored")
    func invalidTargets() {
        let model = CadenceAppModel.preview()

        model.requestOpenAlbumContextually(id: "missing")
        model.requestOpenArtistContextually(id: "missing")

        #expect(model.contextualNavigationHistory.isEmpty)
        #expect(model.selectedDestination == .library)
    }

    @Test("Dirty Smart Collection asks before contextual navigation")
    func dirtySmartCollectionGuard() throws {
        let model = CadenceAppModel.preview()
        let album = try #require(model.albums.first)
        model.requestNavigationDestination(.smartCollections)
        #expect(model.requestEditSelectedSmartCollection())
        model.mutateSmartCollectionDraft { $0.name += " changed" }

        model.requestOpenAlbumContextually(album)

        #expect(
            model.pendingSmartCollectionTransition
                == .contextualRoute(.album(album.id))
        )
        #expect(model.selectedDestination == .smartCollections)

        #expect(
            model.resolvePendingSmartCollectionTransition(.discard)
        )
        #expect(model.selectedDestination == .albums)
        #expect(model.presentedAlbum?.id == album.id)
    }

    @Test("Production routes use UUID identities and restore their source")
    func productionRouteRoundTrip() async {
        let model = CadenceAppModel.production(
            librarySession: .startup(
                location: ManagedLibraryLocation(
                    musicDirectory: FileManager.default.temporaryDirectory
                        .appending(path: UUID().uuidString)
                )
            )
        )
        let artistID = UUID()
        model.selectedDestination = .library
        await model.librarySession.store.searchCatalog("North")

        model.requestOpenProductionArtistContextually(id: artistID)

        #expect(model.selectedDestination == .artists)
        #expect(model.selectedProductionArtistID == artistID)
        #expect(model.hasContextualBackNavigation)
        #expect(model.librarySession.store.catalogSearchQuery.isEmpty)

        model.requestContextualBack()

        #expect(model.selectedDestination == .library)
        #expect(model.selectedProductionArtistID == nil)
        #expect(model.librarySession.store.catalogSearchQuery == "North")
    }
}
