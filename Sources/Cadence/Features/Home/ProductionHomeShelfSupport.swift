import QenTerraMediaComponents
import SwiftUI

private enum HomeHorizontalShelfEdge: Hashable {
    case leading
    case trailing
}

private struct HomeHorizontalShelfContentWidthKey: PreferenceKey {
    static let defaultValue = CGFloat.zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HomeHorizontalShelfViewportWidthKey: PreferenceKey {
    static let defaultValue = CGFloat.zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct HomeHorizontalShelf<Content: View>: View {
    @ViewBuilder let content: Content

    @State private var contentWidth = CGFloat.zero
    @State private var viewportWidth = CGFloat.zero

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        Color.clear
                            .frame(width: 0, height: 1)
                            .id(HomeHorizontalShelfEdge.leading)
                        HStack(alignment: .top, spacing: CadenceLayout.contentGap) {
                            content
                        }
                        Color.clear
                            .frame(width: 0, height: 1)
                            .id(HomeHorizontalShelfEdge.trailing)
                    }
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: HomeHorizontalShelfContentWidthKey.self,
                                value: geometry.size.width
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: HomeHorizontalShelfViewportWidthKey.self,
                            value: geometry.size.width
                        )
                    }
                }

                if contentWidth > viewportWidth + 2 {
                    HStack {
                        shelfArrow(systemImage: "chevron.left") {
                            withAnimation(.smooth(duration: CadenceTheme.motionDismiss)) {
                                proxy.scrollTo(HomeHorizontalShelfEdge.leading, anchor: .leading)
                            }
                        }
                        Spacer()
                        shelfArrow(systemImage: "chevron.right") {
                            withAnimation(.smooth(duration: CadenceTheme.motionDismiss)) {
                                proxy.scrollTo(HomeHorizontalShelfEdge.trailing, anchor: .trailing)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .allowsHitTesting(true)
                }
            }
        }
        .onPreferenceChange(HomeHorizontalShelfContentWidthKey.self) {
            contentWidth = $0
        }
        .onPreferenceChange(HomeHorizontalShelfViewportWidthKey.self) {
            viewportWidth = $0
        }
    }

    private func shelfArrow(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 52)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemImage == "chevron.left" ? "Previous items" : "Next items")
    }
}
