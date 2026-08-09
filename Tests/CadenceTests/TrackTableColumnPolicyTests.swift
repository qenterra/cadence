@testable import Cadence
import Foundation
import Testing

struct TrackTableColumnPolicyTests {
    @Test("Visible columns consume the available row width")
    func columnsConsumeAvailableWidth() {
        let columns: [TrackTableColumn] = [.album, .year, .time]
        let widths = TrackTableColumnPolicy.layout(
            availableWidth: 920,
            columns: columns,
            preferred: nil
        )

        let contentWidth = widths.song + columns.reduce(0) {
            $0 + widths[$1]
        }
        #expect(abs(contentWidth - 920) < 0.5)
    }

    @Test("Every surface uses the same proportional defaults")
    func commonDefaultProportions() {
        let columns: [TrackTableColumn] = [.album, .year, .time]
        let library = TrackTableColumnPolicy.layout(
            availableWidth: 860,
            columns: columns,
            preferred: nil
        )
        let playlist = TrackTableColumnPolicy.layout(
            availableWidth: 860,
            columns: columns,
            preferred: nil
        )

        #expect(library == playlist)
    }

    @Test("Narrow surfaces collapse secondary columns")
    func narrowWidthUsesCompactMode() {
        #expect(TrackTableColumnPolicy.mode(availableWidth: 620) == .compact)
        #expect(TrackTableColumnPolicy.mode(availableWidth: 920) == .full)
    }

    @Test("Row chrome and columns fit without horizontal scrolling")
    func rowFitsViewport() {
        let available = 840.0
        let columns: [TrackTableColumn] = [.album, .year, .time]
        let content = TrackTableColumnPolicy.contentWidth(
            availableWidth: available,
            columns: columns
        )
        let widths = TrackTableColumnPolicy.layout(
            availableWidth: content,
            columns: columns,
            preferred: nil
        )
        let occupied = widths.song + columns.reduce(0) {
            $0 + widths[$1]
        } + TrackTableColumnPolicy.rowChromeWidth(columnCount: columns.count)

        #expect(abs(occupied - available) < 0.5)
    }
}
