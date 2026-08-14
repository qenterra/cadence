import SwiftUI

enum WorkspaceLayout {
    static let paneMinimumWidth: CGFloat = 230
    static let paneMaximumWidth: CGFloat = 420
    static let paneHeaderHeight: CGFloat = 64
    static let paneHeaderInset = CadenceLayout.contentGap
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
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.title2.bold())
                Spacer()
                trailing()
            }
            .padding(.horizontal, WorkspaceLayout.paneHeaderInset)
            .frame(height: WorkspaceLayout.paneHeaderHeight)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
        }
    }
}

extension WorkspacePaneHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) {
            EmptyView()
        }
    }
}
