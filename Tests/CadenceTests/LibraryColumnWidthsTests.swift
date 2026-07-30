@testable import Cadence
import CoreGraphics
import Testing

struct LibraryColumnWidthsTests {
    @Test(
        "Supported window widths preserve every column minimum",
        arguments: [1006.0, 1438.0, 1726.0]
    )
    func columnMinimums(totalWidth: Double) {
        let width = CGFloat(totalWidth)
        let widths = LibraryColumnWidths(totalWidth: width)

        #expect(widths.artists >= 260)
        #expect(widths.albums >= 300)
        #expect(widths.tracks >= 390)
        #expect(abs(widths.artists + widths.albums + widths.tracks - (width - 2)) < 0.001)
    }

    @Test("Wide windows cap browsing columns and give remaining space to tracks")
    func wideWindowCaps() {
        let widths = LibraryColumnWidths(totalWidth: 1726)

        #expect(widths.artists == 410)
        #expect(widths.albums == 460)
        #expect(widths.tracks == 854)
    }
}
