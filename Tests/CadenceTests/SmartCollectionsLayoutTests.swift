@testable import Cadence
import Testing

struct SmartCollectionsLayoutTests {
    @Test("Listening panes expose practical native split-view limits")
    func listeningPaneConstraints() {
        let list = SmartCollectionsPaneConstraints.list

        #expect(list.minimum == 220)
        #expect(list.ideal == 250)
        #expect(list.maximum == 380)
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
