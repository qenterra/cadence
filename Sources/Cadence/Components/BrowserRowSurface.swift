import SwiftUI

enum BrowserRowSelectionAdornment: Equatable, Sendable {
    case none
    case fill
    case strongFill
}

enum BrowserRowOutlinePresentation: Equatable, Sendable {
    case none
    case focus
}

enum CadenceRowButtonPressPresentation {
    static func opacity(isPressed: Bool) -> Double {
        isPressed ? 0.72 : 1
    }
}

struct BrowserRowVisualState: Equatable, Sendable {
    let selectionAdornment: BrowserRowSelectionAdornment
    let hasHoverFill: Bool
    let outlinePresentation: BrowserRowOutlinePresentation
    let borderWidth: Double

    init(
        isSelected: Bool,
        isHovered: Bool = false,
        isFocused: Bool = false,
        isIncreasedContrast: Bool = false
    ) {
        selectionAdornment = if isSelected {
            isIncreasedContrast ? .strongFill : .fill
        } else {
            .none
        }
        hasHoverFill = !isSelected && isHovered
        outlinePresentation = isFocused ? .focus : .none
        borderWidth = isFocused && isIncreasedContrast ? 2 : 0.5
    }
}

struct BrowserRowSurface: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .contentShape(Rectangle())
            .background(fill(for: state))
            .overlay {
                if state.outlinePresentation == .focus {
                    RoundedRectangle(
                        cornerRadius: CadenceTheme.radiusControl,
                        style: .continuous
                    )
                    .stroke(
                        CadenceTheme.primaryAccent,
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
                reduceMotion
                    ? nil
                    : .easeOut(duration: CadenceTheme.motionPress),
                value: state
            )
    }

    private func fill(for state: BrowserRowVisualState) -> Color {
        switch state.selectionAdornment {
        case .fill: CadenceTheme.selectionFill
        case .strongFill: CadenceTheme.selectionStrongFill
        case .none: state.hasHoverFill ? CadenceTheme.hoverFill : .clear
        }
    }
}

struct CadenceRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(
                CadenceRowButtonPressPresentation.opacity(
                    isPressed: configuration.isPressed
                )
            )
    }
}
