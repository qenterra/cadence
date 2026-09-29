import AppKit
@testable import Cadence
import Foundation
import Testing

struct ReportedUIRegressionTests {
    @Test("Home does not expose Smart Collection cards")
    func homeDoesNotExposeSmartCollectionCards() throws {
        let viewSource = try productionSource(
            "Features/Home/ProductionHomeView.swift"
        )
        let sectionsSource = try productionSource(
            "Features/Home/ProductionHomeView+Sections.swift"
        )
        let supportSource = try productionSource(
            "Features/Home/ProductionHomeSupport.swift"
        )
        let pinStoreSource = try productionSource(
            "Features/Home/HomePinStore.swift"
        )
        let collectionListSource = try productionSource(
            "Features/SmartCollections/SmartCollectionListColumn.swift"
        )

        #expect(!viewSource.contains("case smartCollections"))
        #expect(!sectionsSource.contains("var smartCollections:"))
        #expect(!supportSource.contains("HomeSmartCollectionCard"))
        #expect(!sectionsSource.contains("pinnedSmartCollections"))
        #expect(!pinStoreSource.contains("case smartCollection"))
        #expect(!collectionListSource.contains("Pin to Home"))
    }

    @Test("The global file-drop affordance is a window overlay")
    func fileDropAffordanceCoversTheWindow() throws {
        let rootSource = try productionSource(
            "Features/Shell/CadenceRootView.swift"
        )
        let overlaySource = try productionSource(
            "Features/ImportMusic/ImportMusicDropOverlay.swift"
        )

        #expect(rootSource.contains(".overlay {\n            if model.isImportDropTargeted"))
        #expect(overlaySource.contains(".background(.ultraThinMaterial)"))
    }

    @Test("The Now Playing add-tag control shares the pill row height")
    func addTagControlSharesPillHeight() throws {
        let source = try productionSource(
            "Features/NowPlaying/ProductionNowPlayingView+Metadata.swift"
        )

        #expect(source.contains("height: CadenceTagPillMetrics.height"))
    }

    @Test("The AirPlay control owns focus instead of handing it to Search")
    func airPlayControlOwnsFocus() throws {
        let source = try productionSource("Components/AirPlayRoutePicker.swift")

        #expect(source.contains("CadenceAirPlayRoutePickerView"))
        #expect(source.contains("override var acceptsFirstResponder: Bool"))
        #expect(source.contains("makeFirstResponder(self)"))
    }

    @MainActor
    @Test("The AirPlay route picker can retain window focus")
    func airPlayRoutePickerCanRetainWindowFocus() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let picker = CadenceAirPlayRoutePickerView(
            frame: CGRect(x: 20, y: 20, width: 34, height: 34)
        )
        window.contentView = picker

        #expect(picker.acceptsFirstResponder)
        #expect(window.makeFirstResponder(picker))
        #expect(window.firstResponder === picker)

        window.orderOut(nil)
    }

    @Test("Detail favorite controls follow Shuffle and use a larger target")
    func detailFavoritesFollowShuffle() throws {
        let artistSource = try productionSource(
            "Features/Artists/ProductionArtistDetailView.swift"
        )
        let albumSource = try productionSource(
            "Features/Albums/ProductionAlbumDetailView.swift"
        )

        #expect(
            artistSource.contains(
                "playbackActions(artist)\n                    artistFavoriteButton(artist)\n                    Spacer"
            )
        )
        #expect(
            albumSource.contains(
                "playbackActions(album)\n                    albumFavoriteButton(album)\n                    Spacer"
            )
        )
        #expect(artistSource.contains("controlSize: 34"))
        #expect(albumSource.contains("controlSize: 34"))
        #expect(artistSource.contains(".imageScale(.large)"))
        #expect(albumSource.contains(".imageScale(.large)"))
    }

    @Test("Album and artist cards keep favorites in their context menus")
    func catalogEntityCardsKeepFavoritesInContextMenus() throws {
        let albumSource = try productionSource(
            "Features/Albums/ProductionAlbumsView.swift"
        )
        let artistSource = try productionSource(
            "Features/Artists/ProductionArtistsView.swift"
        )

        #expect(!albumSource.contains("FavoriteButton("))
        #expect(!artistSource.contains("FavoriteButton("))
        #expect(albumSource.contains("FavoriteContextMenuItem("))
        #expect(artistSource.contains("FavoriteContextMenuItem("))
    }

    @Test("Every album and artist context-menu surface exposes favorites")
    func allCatalogContextMenusExposeFavorites() throws {
        let expectedCounts = [
            "Features/Albums/ProductionAlbumsView.swift": 1,
            "Features/Albums/ProductionAlbumDetailView.swift": 1,
            "Features/Artists/ProductionArtistsView.swift": 1,
            "Features/Artists/ProductionArtistDetailView.swift": 2,
            "Features/Library/ProductionLibraryView.swift": 2,
            "Features/Search/ProductionSearchResultsView+Components.swift": 2,
        ]

        for (path, expectedCount) in expectedCounts {
            let source = try productionSource(path)
            #expect(
                source.components(separatedBy: "FavoriteContextMenuItem(")
                    .count - 1 == expectedCount
            )
        }
    }

    @Test("Track-only context menus expose favorites where no row heart exists")
    func standaloneTrackContextMenusExposeFavorites() throws {
        let nowPlayingSource = try productionSource(
            "Features/NowPlaying/ProductionNowPlayingView.swift"
        )
        let queueSource = try productionSource(
            "Features/NowPlaying/ProductionPlaybackQueueRow.swift"
        )

        #expect(nowPlayingSource.contains("FavoriteContextMenuItem("))
        #expect(queueSource.contains("FavoriteContextMenuItem("))
    }

    @Test("Entity eyebrow labels share the compact title spacing")
    func entityEyebrowsShareCompactTitleSpacing() throws {
        let sources = try [
            "Features/Artists/ProductionArtistDetailView.swift",
            "Features/Albums/ProductionAlbumDetailView.swift",
            "Features/Playlists/PlaylistsView.swift",
            "Features/SmartCollections/SmartCollectionListeningHeader.swift",
        ].map(productionSource)

        #expect(sources.allSatisfy { $0.contains("CatalogDetailEyebrow(") })
    }

    @Test("Catalog editors expose direct artwork actions instead of an Artwork menu")
    func editorsUseDirectArtworkActions() throws {
        let editorSource = try productionSource(
            "Components/CatalogEntityEditorSheet.swift"
        )
        let smartCollectionSource = try productionSource(
            "Features/SmartCollections/SmartCollectionRuleBuilder.swift"
        )

        #expect(!editorSource.contains("Menu(\"Artwork\""))
        #expect(!smartCollectionSource.contains("Menu(\"Artwork\""))
        #expect(editorSource.contains("ArtworkActionButtons("))
        #expect(smartCollectionSource.contains("ArtworkActionButtons("))
    }

    private func productionSource(_ relativePath: String) throws -> String {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root
                .appending(path: "Sources/Cadence")
                .appending(path: relativePath),
            encoding: .utf8
        )
    }
}
