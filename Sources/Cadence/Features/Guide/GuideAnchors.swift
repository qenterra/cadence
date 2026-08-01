import SwiftUI

struct GuideAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [GuideAnchor: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [GuideAnchor: Anchor<CGRect>],
        nextValue: () -> [GuideAnchor: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

extension View {
    func guideAnchor(_ guideAnchor: GuideAnchor) -> some View {
        anchorPreference(
            key: GuideAnchorPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [guideAnchor: anchor]
        }
    }

    @ViewBuilder
    func guideAnchor(_ guideAnchor: GuideAnchor?) -> some View {
        if let guideAnchor {
            self.guideAnchor(guideAnchor)
        } else {
            self
        }
    }
}
