import AppKit
import SwiftUI

enum CadenceAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self {
        self
    }

    var title: String {
        rawValue.capitalized
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}

enum CadenceTheme {
    static let primaryAccent = dynamicColor(
        light: NSColor(
            calibratedRed: 0.10,
            green: 0.10,
            blue: 0.11,
            alpha: 1
        ),
        dark: .white
    )

    static let contentBackground = dynamicColor(
        light: NSColor(
            calibratedRed: 0.955,
            green: 0.955,
            blue: 0.965,
            alpha: 1
        ),
        dark: NSColor(
            calibratedRed: 23 / 255,
            green: 23 / 255,
            blue: 25 / 255,
            alpha: 1
        )
    )

    static let secondarySurface = dynamicColor(
        light: NSColor(
            calibratedRed: 0.91,
            green: 0.91,
            blue: 0.925,
            alpha: 1
        ),
        dark: NSColor(
            calibratedRed: 32 / 255,
            green: 32 / 255,
            blue: 35 / 255,
            alpha: 1
        )
    )

    static let opaqueSurface = dynamicColor(
        light: NSColor(
            calibratedRed: 0.88,
            green: 0.88,
            blue: 0.90,
            alpha: 1
        ),
        dark: NSColor(
            calibratedRed: 39 / 255,
            green: 39 / 255,
            blue: 43 / 255,
            alpha: 1
        )
    )

    static let separator = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.12),
        dark: NSColor.white.withAlphaComponent(0.13)
    )
    static let strongSeparator = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.22),
        dark: NSColor.white.withAlphaComponent(0.24)
    )
    static let subduedFill = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.055),
        dark: NSColor.white.withAlphaComponent(0.07)
    )
    static let selectionFill = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.075),
        dark: NSColor.white.withAlphaComponent(0.085)
    )
    static let increasedContrastSelectionFill = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.14),
        dark: NSColor.white.withAlphaComponent(0.14)
    )
    static let hoverFill = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.045),
        dark: NSColor.white.withAlphaComponent(0.045)
    )

    private static func dynamicColor(
        light: NSColor,
        dark: NSColor
    ) -> Color {
        Color(
            nsColor: NSColor(
                name: nil
            ) { appearance in
                appearance.bestMatch(
                    from: [.darkAqua, .aqua]
                ) == .darkAqua ? dark : light
            }
        )
    }
}
