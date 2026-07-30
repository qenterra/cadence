import SwiftUI

struct CadenceSeparator: View {
    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(CadenceTheme.separator)
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
            .accessibilityHidden(true)
    }
}
