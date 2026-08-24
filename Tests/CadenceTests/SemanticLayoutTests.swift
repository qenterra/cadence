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

    @Test("Catalog cards keep one fixed width while column count changes")
    func fixedCatalogCardMetrics() {
        let widths: [CGFloat] = [640, 960, 1280]
        let columns = widths.map {
            CatalogCardLayoutMetrics.columns(
                availableWidth: $0,
                spacing: CadenceLayout.contentGap
            )
        }

        #expect(columns.map(\.count) == [3, 4, 6])
        for columnSet in columns {
            for column in columnSet {
                guard case let .fixed(width) = column.size else {
                    Issue.record("Catalog grid emitted a resizable column")
                    continue
                }
                #expect(width == CatalogCardLayoutMetrics.cardWidth)
                #expect(width == 196)
            }
        }
    }

    @Test("Primary layout regions use bounded semantic metrics")
    func primaryRegionMetrics() {
        #expect(PlayerBarLayoutMetrics.height == 96)
        #expect(PlayerBarLayoutMetrics.horizontalInset == CadenceLayout.panelInset)
        #expect(NavigationRailMetrics.rowHeight == CadenceLayout.rowHeight)
        #expect(NavigationRailMetrics.horizontalInset == CadenceLayout.compactGap)
        #expect(CadenceLayout.readableContentWidth == 760)
    }
}
