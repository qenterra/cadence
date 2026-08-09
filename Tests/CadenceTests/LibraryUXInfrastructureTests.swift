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
    func navigationConfiguration() {
        let order = "tags,albums,tags,settings,unknown"
        let hidden = "albums,trash"
        let visible = NavigationRailConfiguration.visibleDestinations(
            orderRawValue: order,
            hiddenRawValue: hidden
        )

        #expect(visible.first == .tags)
        #expect(!visible.contains(.albums))
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

    @Test("Navigation rail destinations move to the dropped row")
    func navigationReordering() {
        let destinations = [
            NavigationDestination.library,
            .albums,
            .artists,
            .tags,
        ]

        #expect(
            NavigationRailConfiguration.moving(
                .library,
                to: .artists,
                in: destinations
            ) == [.albums, .artists, .library, .tags]
        )
        #expect(
            NavigationRailConfiguration.moving(
                .tags,
                to: .albums,
                in: destinations
            ) == [.library, .tags, .albums, .artists]
        )
        #expect(
            NavigationRailConfiguration.moving(
                .albums,
                to: .albums,
                in: destinations
            ) == destinations
        )
    }

    @Test("Navigation rail rows stay inside collapsed and expanded bounds")
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
            NavigationRailMetrics.contentWidth(isExpanded: false) == 52
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
            dateAdded: .now,
            lastPlayedAt: nil,
            playCount: 0,
            hasSynchronizedLyrics: false
        )
    }
}
