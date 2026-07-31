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
}
