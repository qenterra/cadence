import QenTerraDesignTokens
import SwiftUI

struct BrowserRowSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    let isSelected: Bool
    let isHovered: Bool
    let isFocused: Bool

    var body: some View {
        QDSInteractiveRowSurface(
            state: QDSInteractiveRowState(
                isHovered: isHovered,
                isFocused: isFocused,
                isSelected: isSelected,
                isIncreasedContrast: contrast == .increased
            ),
            appearance: colorScheme == .dark ? .dark : .light
        ) {
            Color.clear.overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(.tint)
                        .frame(width: 2, height: 20)
                        .padding(.leading, 3)
                }
            }
        }
    }
}

struct CadenceRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .symbolEffect(
                .bounce.down,
                options: .nonRepeating,
                isActive: configuration.isPressed && !reduceMotion
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: CadenceTheme.motionPress),
                value: configuration.isPressed
            )
    }
}
