@testable import Cadence
import SwiftUI
import Testing

struct SemanticLayoutTests {
    @Test("Product spacing aliases follow the four-point rhythm")
    func semanticSpacingRhythm() {
        let values = [
            CadenceLayout.textStack,
            CadenceLayout.compactGap,
            CadenceLayout.controlGap,
            CadenceLayout.contentGap,
            CadenceLayout.panelInset,
            CadenceLayout.pageInset,
            CadenceLayout.sectionGap,
        ]

        #expect(values.allSatisfy { $0 > 0 && $0.truncatingRemainder(dividingBy: 4) == 0 })
        #expect(CadenceLayout.pageInset == 24)
        #expect(CadenceLayout.sectionGap == 32)
    }

    @Test("Shared workspace metrics use semantic product roles")
    func sharedWorkspaceMetrics() {
        #expect(WorkspaceLayout.pageInset == CadenceLayout.pageInset)
        #expect(WorkspaceLayout.listInset == CadenceLayout.compactGap)
        #expect(WorkspaceLayout.rowHeight == CadenceLayout.rowHeight)
        #expect(TrackTableColumnPolicy.horizontalInset == CadenceLayout.pageInset)
        #expect(TrackTableColumnPolicy.columnSpacing == CadenceLayout.controlGap)
    }

    @Test("Home uses one artwork-card presentation even without custom artwork")
    func homeTilePresentation() {
        #expect(HomeTilePresentation.resolve(hasArtwork: true) == .artworkCard)
        #expect(HomeTilePresentation.resolve(hasArtwork: false) == .artworkCard)
        #expect(HomeLayoutMetrics.titleLineLimit == 2)
        #expect(HomeLayoutMetrics.subtitleLineLimit == 1)
        #expect(HomeLayoutMetrics.artworkCardHeight < 264)
    }

    @Test("Catalog grids add useful columns without inflating artwork")
    func adaptiveCatalogCardMetrics() {
        let widths: [CGFloat] = [640, 960, 1280]
        let spacing = CadenceLayout.contentGap
        let columns = widths.map {
            CatalogCardLayoutMetrics.columns(
                availableWidth: $0,
                spacing: spacing
            )
        }

        #expect(CatalogCardLayoutMetrics.minimumCardWidth == 164)
        #expect(CatalogCardLayoutMetrics.maximumCardWidth == 196)
        #expect(columns.map(\.count) == [3, 5, 7])
        for (availableWidth, columnSet) in zip(widths, columns) {
            var resolvedWidths: [CGFloat] = []
            for column in columnSet {
                guard case let .fixed(width) = column.size else {
                    Issue.record("Catalog width calculation must be deterministic")
                    continue
                }
                resolvedWidths.append(width)
                #expect(
                    width >= CatalogCardLayoutMetrics.minimumCardWidth
                )
                #expect(
                    width <= CatalogCardLayoutMetrics.maximumCardWidth
                )
            }
            let occupiedWidth = resolvedWidths.reduce(0, +)
                + CGFloat(max(columnSet.count - 1, 0)) * spacing
            #expect(occupiedWidth <= availableWidth)
            #expect(
                availableWidth - occupiedWidth
                    < CatalogCardLayoutMetrics.minimumCardWidth + spacing
            )
        }

        let layoutColumn = CatalogCardLayoutMetrics.layoutColumns(
            spacing: spacing
        )[0]
        if case let .adaptive(minimum, maximum) = layoutColumn.size {
            #expect(minimum == CatalogCardLayoutMetrics.minimumCardWidth)
            #expect(maximum == CatalogCardLayoutMetrics.maximumCardWidth)
        } else {
            Issue.record("Runtime catalog grid must use adaptive columns")
        }
    }

    @Test("Primary layout regions use bounded semantic metrics")
    func primaryRegionMetrics() {
        #expect(PlayerBarLayoutMetrics.height == 96)
        #expect(PlayerBarLayoutMetrics.horizontalInset == CadenceLayout.panelInset)
        #expect(
            PlayerBarLayoutMetrics.metadataMaximumWidth
                > PlayerBarLayoutMetrics.metadataMinimumWidth
        )
        #expect(PlayerBarLayoutMetrics.outputWidth == 244)
        #expect(NavigationRailMetrics.rowHeight == CadenceLayout.rowHeight)
        #expect(NavigationRailMetrics.horizontalInset == CadenceLayout.compactGap)
        #expect(CadenceLayout.readableContentWidth == 760)
    }

    @Test("Player content is optically centered above the bottom edge")
    func playerBarContentFrame() {
        let frame = PlayerBarLayoutMetrics.contentFrame(
            availableWidth: 1200
        )

        #expect(frame.minY == 16)
        #expect(frame.midY == PlayerBarLayoutMetrics.height / 2 - 4)
        #expect(frame.maxY == 72)
        #expect(frame.width == 1200)
    }

    @Test("An internal track exposes its favorite action in transport")
    func playerBarFavoritePlacement() {
        #expect(
            PlayerBarFavoriteRegion.resolve(
                hasPlaybackItem: true,
                isExternal: false
            ) == .transport
        )
        #expect(
            PlayerBarFavoriteRegion.resolve(
                hasPlaybackItem: true,
                isExternal: true
            ) == .hidden
        )
        #expect(
            PlayerBarFavoriteRegion.resolve(
                hasPlaybackItem: false,
                isExternal: false
            ) == .hidden
        )
    }

    @Test("Home puts Recently Played before personalized pinned shelves")
    func homeSectionOrder() {
        #expect(HomeContentSection.personalizedOrder == [
            .recentlyPlayed,
            .pinned,
            .favorites,
        ])
    }
}
