import AppKit
@testable import Cadence
import Foundation
import Testing

struct NavigationRailTests {
    @Test("Navigation rows keep selection surfaces visually separate")
    func navigationRowSpacing() {
        #expect(NavigationRailMetrics.rowSpacing == 2)
    }

    @Test("Navigation rail order is sanitized and hidden pages stay hidden")
    func navigationConfiguration() throws {
        let favorites = try #require(
            NavigationDestination(rawValue: "favorites")
        )
        let visible = NavigationRailConfiguration.visibleDestinations(
            orderRawValue: "tags,albums,tags,settings,unknown",
            hiddenRawValue: "library,trash"
        )

        #expect(visible == [
            .home,
            .tags,
            .albums,
            favorites,
            .allTracks,
            .artists,
            .playlists,
            .smartCollections,
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

    @Test("Navigation uses distinct Browse and Tracks labels")
    func navigationDestinationTitles() {
        #expect(NavigationDestination.library.title == "Browse")
        #expect(NavigationDestination.allTracks.title == "Tracks")
        #expect(
            NavigationDestination.library.accessibilityDescription
                == "Browse artists, albums, and tracks"
        )
        #expect(
            NavigationDestination.allTracks.accessibilityDescription
                == "View every track in the library"
        )
    }

    @Test("Navigation destinations form stable semantic sections")
    func navigationSections() {
        #expect(
            NavigationRailConfiguration.visibleSections(
                orderRawValue: NavigationRailConfiguration.defaultOrderRawValue,
                hiddenRawValue: ""
            ) == [
                NavigationRailSection(
                    group: .listen,
                    destinations: [.home, .favorites]
                ),
                NavigationRailSection(
                    group: .library,
                    destinations: [.library, .allTracks, .albums, .artists]
                ),
                NavigationRailSection(
                    group: .organize,
                    destinations: [
                        .playlists,
                        .smartCollections,
                        .tags,
                        .importMusic,
                    ]
                ),
            ]
        )
        #expect(NavigationRailGroup.allCases.map(\.title) == [
            "Listen",
            "Library",
            "Organize",
        ])
    }

    @Test("Saved order is preserved only inside each semantic section")
    func groupedNavigationPersistence() {
        let sections = NavigationRailConfiguration.visibleSections(
            orderRawValue: "tags,artists,home,importMusic,albums,favorites,"
                + "library,playlists,smartCollections,allTracks",
            hiddenRawValue: "importMusic,albums"
        )

        #expect(sections == [
            NavigationRailSection(
                group: .listen,
                destinations: [.home, .favorites]
            ),
            NavigationRailSection(
                group: .library,
                destinations: [.artists, .library, .allTracks]
            ),
            NavigationRailSection(
                group: .organize,
                destinations: [.tags, .playlists, .smartCollections]
            ),
        ])
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
            favorites,
            .allTracks,
            .playlists,
            .smartCollections,
            .tags,
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
            favorites,
            .library,
            .allTracks,
            .albums,
            .artists,
            .playlists,
            .smartCollections,
            .tags,
            .importMusic,
        ])
        #expect(FavoriteCatalogSection.allCases.map(\.title) == [
            "Tracks",
            "Albums",
            "Artists",
        ])
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
                NSImage(
                    systemSymbolName: $0.symbolName,
                    accessibilityDescription: nil
                ) != nil
            }
        )
    }

    @Test("Navigation rail destinations move freely while Home stays first")
    func navigationReordering() throws {
        let favorites = try #require(
            NavigationDestination(rawValue: "favorites")
        )
        let destinations = [
            NavigationDestination.home,
            favorites,
            .library,
            .allTracks,
        ]

        #expect(
            NavigationRailConfiguration.moving(
                .allTracks,
                to: favorites,
                in: destinations
            ) == [.home, .allTracks, favorites, .library]
        )
        #expect(
            NavigationRailConfiguration.moving(
                .library,
                to: .home,
                in: destinations
            ) == [.home, .library, favorites, .allTracks]
        )
        #expect(
            NavigationRailConfiguration.moving(
                .home,
                to: .allTracks,
                in: destinations
            ) == destinations
        )
        #expect(
            NavigationRailConfiguration.moving(
                .home,
                to: .home,
                in: destinations
            ) == destinations
        )
    }

    @Test("Cross-category navigation order is persisted without duplicates")
    func crossCategoryNavigationReordering() throws {
        let original = NavigationRailConfiguration.configurableDestinations
        let tagsBeforeAlbums = NavigationRailConfiguration.moving(
            .tags,
            to: .albums,
            in: original
        )
        let artistsAfterImport = NavigationRailConfiguration.moving(
            .artists,
            to: .importMusic,
            in: tagsBeforeAlbums
        )

        #expect(try #require(tagsBeforeAlbums.firstIndex(of: .tags)) < tagsBeforeAlbums.firstIndex(of: .albums)!)
        #expect(artistsAfterImport.first == .home)
        #expect(artistsAfterImport.last == .artists)
        #expect(Set(artistsAfterImport).count == original.count)
        #expect(Set(artistsAfterImport) == Set(original))
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

    @Test("Navigation rail metrics retain row size, spacing, and chrome inset")
    func navigationRailMetrics() {
        #expect(NavigationRailMetrics.rowHeight == 48)
        #expect(NavigationRailMetrics.rowSpacing > 0)
        #expect(NavigationRailMetrics.rowSurfaceInset > 0)
    }

    @Test("Navigation controls do not animate shared symbols when pressed")
    func navigationControlPressPresentation() {
        #expect(
            CadenceRowButtonPressPresentation.opacity(isPressed: true) == 0.72
        )
    }

    @Test("Navigation rail icons are static and chrome stays inset")
    func navigationRailSourceContract() throws {
        let source = try navigationRailSource()
        let railLabelStart = try #require(
            source.range(of: "private func railLabel")
        )
        let railIconStart = try #require(
            source.range(of: "private func railIcon")
        )
        let railLabelSource = String(
            source[railLabelStart.lowerBound ..< railIconStart.lowerBound]
        )
        let railLabelFramePattern =
            #"\.frame\(\s*width:\s*NavigationRailMetrics\.rowWidth\(isExpanded:\s*isExpanded\),"#
                + #"\s*height:\s*NavigationRailMetrics\.rowHeight\s*\)"#
        let surfaceInsetPattern =
            #"\.background\s*\{\s*BrowserRowSurface\([\s\S]*?\)\s*"#
                + #"\.padding\(\.horizontal,\s*NavigationRailMetrics\.rowSurfaceInset\)\s*\}"#

        #expect(!source.contains("activationCounts"))
        #expect(!source.contains(".symbolEffect("))
        #expect(!source.contains(".contentTransition("))
        #expect(!source.contains(".buttonStyle(CadenceRowButtonStyle())"))
        #expect(
            railLabelSource.range(
                of: railLabelFramePattern,
                options: .regularExpression
            ) != nil
        )
        #expect(
            source.components(
                separatedBy: "NavigationRailMetrics.rowSurfaceInset"
            ).count == 2
        )
        #expect(
            source.range(
                of: surfaceInsetPattern,
                options: .regularExpression
            ) != nil
        )
    }

    private func navigationRailSource() throws -> String {
        let sourceURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(
                path: "Sources/Cadence/Components/NavigationRail.swift"
            )
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
