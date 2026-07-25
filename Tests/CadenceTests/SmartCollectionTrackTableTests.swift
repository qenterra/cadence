@testable import Cadence
import CoreGraphics
import Testing

struct SmartCollectionTrackTableTests {
    @Test("Compact table columns fill the available width")
    func compactColumns() {
        let columns = SmartCollectionTrackTableColumnWidths(totalWidth: 727)

        #expect(columns.index == 40)
        #expect(columns.title >= 160)
        #expect(columns.artist >= 130)
        #expect(columns.album >= 180)
        #expect(columns.year == 58)
        #expect(columns.format == 72)
        #expect(columns.duration == 58)
        #expect(abs(columns.total - 727) < 0.001)
    }

    @Test("Flexible metadata columns absorb wider windows")
    func widerColumns() {
        let compact = SmartCollectionTrackTableColumnWidths(totalWidth: 727)
        let wide = SmartCollectionTrackTableColumnWidths(totalWidth: 1100)

        #expect(wide.title > compact.title)
        #expect(wide.artist > compact.artist)
        #expect(wide.album > compact.album)
        #expect(abs(wide.total - 1100) < 0.001)
    }
}
