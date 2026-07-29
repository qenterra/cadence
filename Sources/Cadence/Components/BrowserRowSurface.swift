import SwiftUI

struct BrowserRowSurface: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    let isSelected: Bool
    let isHovered: Bool
    let isFocused: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(fillColor)
            .overlay {
                if isFocused || (contrast == .increased && isSelected) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            boundaryColor,
                            lineWidth: isFocused && contrast == .increased ? 2 : 1
                        )
                }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(.tint)
                        .frame(width: 2, height: 20)
                        .padding(.leading, 3)
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: isHovered
            )
    }

    private var fillColor: Color {
        if isSelected {
            return contrast == .increased
                ? CadenceTheme.increasedContrastSelectionFill
                : CadenceTheme.selectionFill
        }
        return isHovered ? CadenceTheme.hoverFill : .clear
    }

    private var focusColor: Color {
        .primary.opacity(contrast == .increased ? 0.8 : 0.72)
    }

    private var boundaryColor: Color {
        isFocused ? focusColor : .primary.opacity(0.52)
    }
}

struct CadenceRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.08),
                value: configuration.isPressed
            )
    }
}
