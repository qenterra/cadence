import QenTerraComponents
import SwiftUI

enum WorkspaceLayout {
    static let paneMinimumWidth: CGFloat = 230
    static let paneMaximumWidth: CGFloat = 420
    static let listInset = CadenceLayout.compactGap
    static let rowHeight = CadenceLayout.rowHeight
    static let pageInset = CadenceLayout.pageInset
}

struct WorkspacePaneHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        QenTerraComponents.WorkspacePaneHeader(
            title,
            presentation: .cadence
        ) {
            trailing()
        }
    }
}
