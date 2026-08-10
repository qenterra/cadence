import SwiftUI

struct CadenceMenuRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .symbolEffect(
                .bounce.down,
                options: .nonRepeating,
                isActive: configuration.isPressed && !reduceMotion
            )
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                configuration.isPressed
                    ? CadenceTheme.selectionFill
                    : .clear,
                in: RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusControl,
                    style: .continuous
                )
            )
    }
}
