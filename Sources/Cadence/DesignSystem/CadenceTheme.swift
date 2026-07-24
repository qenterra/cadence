import SwiftUI

enum CadenceTheme {
    static let accent = Color.white
    static let contentBackground = Color(
        red: 23 / 255,
        green: 23 / 255,
        blue: 25 / 255
    )
    static let secondarySurface = Color(
        red: 32 / 255,
        green: 32 / 255,
        blue: 35 / 255
    )
    static let opaqueSurface = Color(
        red: 39 / 255,
        green: 39 / 255,
        blue: 43 / 255
    )
    static let separator = Color.white.opacity(0.09)
    static let subduedFill = Color.white.opacity(0.07)
    static let selectionFill = Color.white.opacity(0.085)
    static let increasedContrastSelectionFill = Color.white.opacity(0.14)
    static let hoverFill = Color.white.opacity(0.045)
}
