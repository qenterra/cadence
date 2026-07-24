@testable import Cadence
import CoreGraphics
import Testing

struct TagsColumnWidthsTests {
    @Test(
        "Supported window widths preserve Tags column minimums",
        arguments: [1006.0, 1438.0, 1726.0]
    )
    func columnMinimums(totalWidth: Double) {
        let width = CGFloat(totalWidth)
        let widths = TagsColumnWidths(totalWidth: width)

        #expect(widths.groups >= 190)
        #expect(widths.tags >= 250)
        #expect(widths.results >= 440)
        #expect(abs(widths.groups + widths.tags + widths.results - (width - 2)) < 0.001)
    }

    @Test("Wide windows prioritize Tags results")
    func wideWindowCaps() {
        let widths = TagsColumnWidths(totalWidth: 1726)

        #expect(widths.groups == 240)
        #expect(widths.tags == 320)
        #expect(widths.results == 1164)
    }

    @Test("Inspector overlays at minimum width and becomes a column when wide")
    func inspectorPresentation() {
        let compact = TagsWorkspaceLayout(
            totalWidth: 1006,
            isInspectorPresented: true
        )
        let wide = TagsWorkspaceLayout(
            totalWidth: 1438,
            isInspectorPresented: true
        )

        #expect(compact.inspectorPresentation == .overlay)
        #expect(compact.columns.results >= 440)
        #expect(wide.inspectorPresentation == .column)
        #expect(wide.inspectorWidth == 320)
        #expect(wide.columns.results >= 440)
    }

    @Test("Inspector width remains within the approved resize bounds")
    func inspectorWidthBounds() {
        let narrowInspector = TagsWorkspaceLayout(
            totalWidth: 1438,
            isInspectorPresented: true,
            requestedInspectorWidth: 260
        )
        let wideInspector = TagsWorkspaceLayout(
            totalWidth: 1438,
            isInspectorPresented: true,
            requestedInspectorWidth: 420
        )

        #expect(narrowInspector.inspectorWidth == 300)
        #expect(wideInspector.inspectorWidth == 360)
    }
}
