@testable import Cadence
import Foundation
import Testing

struct TrackTableColumnPolicyTests {
    @Test("Visible columns consume the available row width")
    func columnsConsumeAvailableWidth() {
        let columns: [TrackTableColumn] = [.album, .year, .time]
        let widths = TrackTableColumnPolicy.layout(
            availableWidth: 920,
            columns: columns
        )

        let contentWidth = widths.song + columns.reduce(0) {
            $0 + widths[$1]
        }
        #expect(abs(contentWidth - 920) < 0.5)
    }

    @Test("Every surface uses the same deterministic column widths")
    func commonFixedWidths() {
        let columns: [TrackTableColumn] = [.album, .year, .time]
        let library = TrackTableColumnPolicy.layout(
            availableWidth: 860,
            columns: columns
        )
        let playlist = TrackTableColumnPolicy.layout(
            availableWidth: 860,
            columns: columns
        )

        #expect(library == playlist)
        #expect(library.album == 190)
        #expect(library.year == 64)
        #expect(library.time == 64)
        #expect(library.song == 542)
    }

    @Test("Narrow surfaces collapse secondary columns")
    func narrowWidthUsesCompactMode() {
        #expect(TrackTableColumnPolicy.mode(availableWidth: 620) == .compact)
        #expect(TrackTableColumnPolicy.mode(availableWidth: 920) == .full)
    }

    @Test("The minimum full viewport protects a 360 point Track column")
    func minimumFullViewportProtectsTrack() {
        let columns: [TrackTableColumn] = [.album, .year, .time]
        let viewport = TrackTableColumnPolicy.compactThreshold
        let content = TrackTableColumnPolicy.contentWidth(
            availableWidth: viewport,
            columns: columns
        )
        let widths = TrackTableColumnPolicy.layout(
            availableWidth: content,
            columns: columns
        )

        #expect(TrackTableColumnPolicy.mode(availableWidth: viewport) == .full)
        #expect(widths.song >= 360)
    }

    @Test("Optional columns collapse before active columns are crushed")
    func compactModeCollapsesOptionalColumns() {
        let viewport = TrackTableColumnPolicy.compactThreshold - 1
        let columns: [TrackTableColumn] = []
        let content = TrackTableColumnPolicy.contentWidth(
            availableWidth: viewport,
            columns: columns
        )
        let widths = TrackTableColumnPolicy.layout(
            availableWidth: content,
            columns: columns
        )

        #expect(TrackTableColumnPolicy.mode(availableWidth: viewport) == .compact)
        #expect(widths.album == 0)
        #expect(widths.year == 0)
        #expect(widths.time == 0)
        #expect(widths.song == content)
    }

    @Test("Row chrome and columns fit without horizontal scrolling")
    func rowFitsViewport() {
        let viewports = [420.0, 720.0, 840.0, 1440.0]
        let columnSets: [[TrackTableColumn]] = [
            [],
            [.album],
            [.album, .year, .time],
        ]

        for available in viewports {
            for columns in columnSets {
                let activeColumns = TrackTableColumnPolicy.mode(
                    availableWidth: available
                ) == .compact ? [] : columns
                let content = TrackTableColumnPolicy.contentWidth(
                    availableWidth: available,
                    columns: activeColumns
                )
                let widths = TrackTableColumnPolicy.layout(
                    availableWidth: content,
                    columns: activeColumns
                )
                let occupied = widths.song + activeColumns.reduce(0) {
                    $0 + widths[$1]
                } + TrackTableColumnPolicy.rowChromeWidth(
                    columnCount: activeColumns.count
                )

                #expect(abs(occupied - available) < 0.5)
            }
        }
    }

    @Test("Track content shares the page inset and compact favorite slot")
    func trackContentMetrics() {
        #expect(
            TrackTableColumnPolicy.horizontalInset
                == WorkspaceLayout.pageInset
        )
        #expect(
            TrackTableColumnPolicy.favoriteControlWidth
                == CatalogTileFavoriteLayout.controlSize
        )
        #expect(
            CatalogTileFavoriteLayout.titleHorizontalInset
                == CatalogTileFavoriteLayout.controlSize + 4
        )
        #expect(TrackTableColumnPolicy.songContentSpacing == 8)
    }

    @Test("Track selection chrome keeps a compact horizontal inset")
    func selectionChromeInset() {
        #expect(TrackTableColumnPolicy.selectionHorizontalInset == 8)
    }
}
