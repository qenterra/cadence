@testable import Cadence
import Testing

struct SemanticLayoutTests {
    @Test("Product spacing aliases follow the four-point QDS rhythm")
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

    @Test("Home uses artwork cards and a compact text fallback")
    func homeTilePresentation() {
        #expect(HomeTilePresentation.resolve(hasArtwork: true) == .artworkCard)
        #expect(HomeTilePresentation.resolve(hasArtwork: false) == .textRow)
        #expect(HomeLayoutMetrics.titleLineLimit == 2)
        #expect(HomeLayoutMetrics.subtitleLineLimit == 1)
        #expect(HomeLayoutMetrics.textRowHeight < HomeLayoutMetrics.artworkCardHeight)
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
