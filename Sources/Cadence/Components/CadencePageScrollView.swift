import SwiftUI

typealias CadenceRefreshAction = @MainActor @Sendable () async -> Void

/// Shared page chrome for vertically scrolling, top-aligned workspaces.
struct CadencePageScrollView<Content: View>: View {
    let maxContentWidth: CGFloat?
    let sectionSpacing: CGFloat
    let refreshAction: CadenceRefreshAction?
    @ViewBuilder let content: Content

    init(
        maxContentWidth: CGFloat? = nil,
        sectionSpacing: CGFloat = CadenceLayout.sectionGap,
        refreshAction: CadenceRefreshAction? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.maxContentWidth = maxContentWidth
        self.sectionSpacing = sectionSpacing
        self.refreshAction = refreshAction
        self.content = content()
    }

    var body: some View {
        if let refreshAction {
            scrollContent.refreshable {
                await refreshAction()
            }
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                content
            }
            .frame(maxWidth: maxContentWidth ?? .infinity, alignment: .leading)
            .padding(.horizontal, CadenceLayout.pageInset)
            .padding(.vertical, CadenceLayout.pageInset)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(CadenceTheme.contentBackground)
    }
}
