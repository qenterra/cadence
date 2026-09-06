import QenTerraComponents
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

    let isSelected: Bool
    let isHovered: Bool
    let isFocused: Bool

    var body: some View {
        InteractiveRowSurface(
            state: InteractiveRowState(
                isHovered: isHovered,
                isFocused: isFocused,
                isSelected: isSelected,
                isIncreasedContrast: contrast == .increased
            )
        ) {
            Color.clear
        }
    }
}

struct CadenceRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowActionButtonStyle(presentation: .contentOnly)
            .makeBody(configuration: configuration)
    }
}
