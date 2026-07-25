@testable import Cadence
import CoreGraphics
import Testing

struct SmartCollectionsLayoutTests {
    @Test("Supported widths keep the collection list stable")
    func minimums() {
        for totalWidth in [1006.0, 1438.0, 1726.0] {
            let width = CGFloat(totalWidth)
            let columns = SmartCollectionsColumnWidths(totalWidth: width)

            #expect((230 ... 260).contains(columns.collections))
            #expect(columns.content >= 775)
            #expect(
                abs(
                    columns.collections + columns.content
                        - (width - 1)
                ) < 0.001
            )
            #expect((390 ... 460).contains(columns.builder))
            #expect(columns.results >= 380)
            #expect(
                abs(
                    columns.collections + columns.builder + columns.results
                        - (width - 2)
                ) < 0.001
            )
        }
    }

    @Test("Wide windows cap the list and builder while content expands")
    func wideWindow() {
        let columns = SmartCollectionsColumnWidths(totalWidth: 1726)

        #expect(columns.collections == 260)
        #expect(columns.content == 1465)
        #expect(columns.builder == 460)
        #expect(columns.results == 1004)
    }
}
