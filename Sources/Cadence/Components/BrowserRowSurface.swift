import SwiftUI

enum BrowserRowFillRole: Equatable, Sendable {
    case none
    case hover
    case selected
    case selectedStrong
}

struct BrowserRowVisualState: Equatable, Sendable {
    let fillRole: BrowserRowFillRole
    let showsBorder: Bool
    let borderWidth: Double

    init(
        isSelected: Bool,
        isHovered: Bool = false,
        isFocused: Bool = false,
        isIncreasedContrast: Bool = false
    ) {
        if isSelected {
            fillRole = isIncreasedContrast ? .selectedStrong : .selected
        } else if isHovered {
            fillRole = .hover
        } else {
            fillRole = .none
        }
        showsBorder = isFocused || isSelected
        borderWidth = isFocused && isIncreasedContrast ? 2 : 0.5
    }
}

struct BrowserRowSurface: View {
    @Environment(\.colorSchemeContrast) private var contrast

    let isSelected: Bool
    let isHovered: Bool
    let isFocused: Bool

    var body: some View {
        let state = BrowserRowVisualState(
            isSelected: isSelected,
            isHovered: isHovered,
            isFocused: isFocused,
            isIncreasedContrast: contrast == .increased
        )
        Color.clear
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(.tint)
                        .frame(width: 2, height: 20)
                        .padding(.leading, 3)
                }
            }
            .contentShape(Rectangle())
            .background(fill(for: state.fillRole))
            .overlay {
                if state.showsBorder {
                    RoundedRectangle(
                        cornerRadius: CadenceTheme.radiusControl,
                        style: .continuous
                    )
                    .stroke(
                        isFocused
                            ? CadenceTheme.primaryAccent
                            : CadenceTheme.strongSeparator,
                        lineWidth: state.borderWidth
                    )
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusControl,
                    style: .continuous
                )
            )
            .animation(
                .easeOut(duration: CadenceTheme.motionPress),
                value: state
            )
    }

    private func fill(
        for role: BrowserRowFillRole
    ) -> Color {
        switch role {
        case .none: .clear
        case .hover: CadenceTheme.hoverFill
        case .selected: CadenceTheme.selectionFill
        case .selectedStrong: CadenceTheme.selectionStrongFill
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
