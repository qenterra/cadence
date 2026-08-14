import SwiftUI

/// Shared page chrome for vertically scrolling, top-aligned workspaces.
struct CadencePageScrollView<Content: View>: View {
    let maxContentWidth: CGFloat?
    let sectionSpacing: CGFloat
    @ViewBuilder let content: Content

    init(
        maxContentWidth: CGFloat? = nil,
        sectionSpacing: CGFloat = CadenceLayout.sectionGap,
        @ViewBuilder content: () -> Content
    ) {
        self.maxContentWidth = maxContentWidth
        self.sectionSpacing = sectionSpacing
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                content
            }
            .frame(maxWidth: maxContentWidth ?? .infinity, alignment: .leading)
            .padding(.horizontal, CadenceLayout.pageInset)
            .padding(.vertical, CadenceLayout.pageInset)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CadenceTheme.contentBackground)
    }
}
