import AppKit
@testable import Cadence
import Foundation
import Testing

struct LibraryUXInfrastructureTests {
    @Test("System appearance releases the explicit AppKit override")
    func appearanceOverrides() {
        #expect(CadenceAppearance.system.appKitAppearance == nil)
        #expect(CadenceAppearance.light.appKitAppearance?.name == .aqua)
        #expect(CadenceAppearance.dark.appKitAppearance?.name == .darkAqua)
    }

    @Test("Track table sorting toggles canonical text and numeric order")
    func trackTableSorting() {
        let tracks = [
            track(title: "Beta", year: 2024),
            track(title: "Alpha", year: 2026),
        ]

        #expect(
            TrackTableSortDescriptor(
                field: .song,
                direction: .ascending
            ).sorted(tracks).map(\.title) == ["Alpha", "Beta"]
        )
        #expect(
            TrackTableSortDescriptor(
                field: .year,
                direction: .descending
            ).sorted(tracks).map(\.year) == [2026, 2024]
        )
    }

    @Test("Navigation rail order is sanitized and hidden pages stay hidden")
    func navigationConfiguration() throws {
        let favorites = try #require(
            NavigationDestination(rawValue: "favorites")
        )
        let order = "tags,albums,tags,settings,unknown"
        let hidden = "library,trash"
        let visible = NavigationRailConfiguration.visibleDestinations(
            orderRawValue: order,
            hiddenRawValue: hidden
        )

        #expect(visible == [
            .home,
            .tags,
            .albums,
            .allTracks,
            .artists,
            favorites,
            .smartCollections,
            .playlists,
            .importMusic,
        ])
        #expect(!visible.contains(.library))
        #expect(!visible.contains(.trash))
        #expect(Set(visible).count == visible.count)
        #expect(
            Set(visible).isSubset(
                of: Set(
                    NavigationRailConfiguration.configurableDestinations
                )
            )
        )
    }

    @Test("Home stays first when an older saved rail order is restored")
    func homeLeadsPersistedNavigationOrder() throws {
        let favorites = try #require(
            NavigationDestination(rawValue: "favorites")
        )
        let restored = NavigationRailConfiguration.orderedDestinations(
            from: "albums,artists,home,library"
        )

        #expect(restored == [
            .home,
            .albums,
            .artists,
            .library,
            .allTracks,
            favorites,
            .tags,
            .smartCollections,
            .playlists,
            .importMusic,
        ])
    }

    @Test("Original destinations stay separate and Favorites has its own route")
    func standaloneNavigationDestinations() throws {
        let favorites = try #require(
            NavigationDestination(rawValue: "favorites")
        )
        #expect(NavigationRailConfiguration.configurableDestinations == [
            .home,
            .library,
            .allTracks,
            .albums,
            .artists,
            favorites,
            .tags,
            .smartCollections,
            .playlists,
            .importMusic,
        ])
        #expect(FavoriteCatalogSection.allCases.map(\.title) == [
            "Songs",
            "Albums",
            "Artists",
        ])
    }

    @Test("Home pin projection tolerates duplicate library and saved identifiers")
    func homePinsDeduplicateIdentifiers() {
        struct Item: Identifiable, Equatable {
            let id: UUID
            let title: String
        }

        let firstID = UUID()
        let secondID = UUID()
        let first = Item(id: firstID, title: "First")
        let duplicate = Item(id: firstID, title: "Duplicate")
        let second = Item(id: secondID, title: "Second")

        let ordered = HomePinStore.orderedItems(
            ids: [firstID, firstID, secondID],
            source: [first, duplicate, second]
        )

        #expect(ordered == [first, second])
    }

    @Test("Home listening shelves stay bounded and continue from the latest item")
    func homeListeningSelection() {
        let items = Array(1 ... 10)

        #expect(HomeListeningSelection.continueTrack(from: items) == 1)
        #expect(HomeListeningSelection.items(items, limit: 6) == Array(1 ... 6))
        #expect(HomeListeningSelection.items(items, limit: 0).isEmpty)
    }

    @Test("New navigation profiles start expanded and every destination symbol is unique")
    func navigationDefaults() {
        #expect(NavigationRailConfiguration.defaultIsExpanded)
        #expect(
            Set(NavigationDestination.allCases.map(\.symbolName)).count
                == NavigationDestination.allCases.count
        )
        #expect(
            NavigationDestination.allCases.allSatisfy {
                NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: nil) != nil
            }
        )
    }

    @Test("Navigation rail destinations move to the dropped row")
    func navigationReordering() throws {
        let favorites = try #require(
            NavigationDestination(rawValue: "favorites")
        )
        let destinations = [
            NavigationDestination.home,
            .library,
            favorites,
        ]

        #expect(
            NavigationRailConfiguration.moving(
                .library,
                to: favorites,
                in: destinations
            ) == [.home, favorites, .library]
        )
        #expect(
            NavigationRailConfiguration.moving(
                favorites,
                to: .home,
                in: destinations
            ) == [favorites, .home, .library]
        )
        #expect(
            NavigationRailConfiguration.moving(
                .home,
                to: .home,
                in: destinations
            ) == destinations
        )
    }

    @Test("Collapsed navigation selection is a symmetric square")
    func navigationRailGeometry() {
        #expect(
            NavigationRailMetrics.contentWidth(isExpanded: false)
                == NavigationRailMetrics.collapsedWidth
                - NavigationRailMetrics.horizontalInset * 2
        )
        #expect(
            NavigationRailMetrics.contentWidth(isExpanded: true)
                == NavigationRailMetrics.expandedWidth
                - NavigationRailMetrics.horizontalInset * 2
        )
        #expect(
            NavigationRailMetrics.rowWidth(isExpanded: false)
                == NavigationRailMetrics.rowHeight
        )
        #expect(NavigationRailMetrics.rowWidth(isExpanded: false) == 42)
    }

    @Test("Navigation rail keeps icons on one axis in both widths")
    func navigationRailIconAxis() {
        #expect(
            NavigationRailMetrics.iconCenterX(isExpanded: false)
                == NavigationRailMetrics.iconCenterX(isExpanded: true)
        )
        #expect(
            NavigationRailMetrics.iconCenterX(isExpanded: false)
                == NavigationRailMetrics.collapsedWidth / 2
        )
    }

    @Test("Track artwork waveform represents only the active playing track")
    @MainActor
    func trackArtworkPlaybackSymbol() {
        #expect(
            ProductionTrackTableRow.artworkOverlaySymbolName(
                isCurrentTrack: true,
                isPlaying: true
            ) == "waveform"
        )
        #expect(
            ProductionTrackTableRow.artworkOverlaySymbolName(
                isCurrentTrack: false,
                isPlaying: true
            ) == "play.fill"
        )
        #expect(
            ProductionTrackTableRow.artworkOverlaySymbolName(
                isCurrentTrack: true,
                isPlaying: false
            ) == "play.fill"
        )
    }

    @Test("Track format pills omit leading file-extension separators")
    @MainActor
    func trackFormatPillTitle() {
        #expect(
            ProductionTrackTableRow.formatPillTitle(".mp3") == "MP3"
        )
        #expect(
            ProductionTrackTableRow.formatPillTitle("flac") == "FLAC"
        )
        #expect(
            ProductionTrackTableRow.formatPillTitle(" ..aac") == "AAC"
        )
    }

    @Test("Production Smart Collections match inherited tag descendants")
    func productionSmartCollectionTags() {
        let genreID = UUID()
        let ambientID = UUID()
        let first = track(title: "Ambient")
        let second = track(title: "Untagged")
        let tags = [
            genreID: LibraryTagProjection(
                id: genreID,
                displayPath: "Genre",
                groupPath: nil
            ),
            ambientID: LibraryTagProjection(
                id: ambientID,
                displayPath: "Genre / Ambient",
                groupPath: "Genre"
            ),
        ]
        let root = SmartCollectionRuleGroup(
            combinator: .all,
            children: [
                .condition(
                    SmartCollectionRuleCondition(
                        field: .tag,
                        operator: .is,
                        value: .tag(
                            id: genreID.uuidString,
                            scope: .includeSubtags
                        )
                    )
                ),
            ]
        )

        let result = ProductionSmartCollectionEvaluator().evaluate(
            root: root,
            index: ProductionSmartCollectionIndex(
                tracks: [first, second],
                effectiveTagIDsByTrackID: [
                    first.id: [ambientID],
                ],
                tagsByID: tags
            )
        )

        #expect(result.map(\.id) == [first.id])
    }

    private func track(
        title: String,
        year: Int = 2026
    ) -> LibraryTrackProjection {
        LibraryTrackProjection(
            id: UUID(),
            title: title,
            artistID: nil,
            artist: "Artist",
            albumID: nil,
            album: "Album",
            duration: 180,
            year: year,
            codec: "flac",
            sampleRate: 44.1,
            channelCount: 2,
            bitDepth: 24,
            isFavorite: false,
            customArtworkID: nil,
            artworkID: nil,
            relativeMediaPath: "\(UUID()).flac",
            lastPlayedAt: nil,
            hasSynchronizedLyrics: false
        )
    }
}
