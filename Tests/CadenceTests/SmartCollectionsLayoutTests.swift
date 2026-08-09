@testable import Cadence
import Testing

struct SmartCollectionsLayoutTests {
    @Test("Listening panes expose practical native split-view limits")
    func listeningPaneConstraints() {
        let list = SmartCollectionsPaneConstraints.list

        #expect(list.minimum == WorkspaceLayout.paneMinimumWidth)
        #expect(list.ideal == 270)
        #expect(list.maximum == WorkspaceLayout.paneMaximumWidth)
        #expect(
            SmartCollectionsPaneConstraints.workspaceMinimum == 720
        )
    }

    @Test("Editor panes remain independently resizable")
    func editorPaneConstraints() {
        let builder = SmartCollectionsPaneConstraints.builder

        #expect(builder.minimum == 360)
        #expect(builder.ideal == 430)
        #expect(builder.maximum == 620)
        #expect(SmartCollectionsPaneConstraints.resultsMinimum == 360)
    }

    @Test("Resizable columns always fill the workspace without overflow")
    func splitLayoutFillsAvailableWidth() {
        let layout = CadenceSplitLayout(
            totalWidth: 859,
            proposedFixedWidth: 620,
            fixedMinimum: 220,
            fixedMaximum: 420,
            flexibleMinimum: 520
        )

        #expect(layout.fixedWidth == 332)
        #expect(layout.flexibleWidth == 520)
        #expect(layout.fixedWidth + layout.dividerWidth + layout.flexibleWidth == 859)

        let undersized = CadenceSplitLayout(
            totalWidth: 200,
            proposedFixedWidth: 420,
            fixedMinimum: 220,
            fixedMaximum: 420,
            flexibleMinimum: 520
        )
        #expect(
            undersized.fixedWidth
                + undersized.dividerWidth
                + undersized.flexibleWidth == 200
        )
    }
}
