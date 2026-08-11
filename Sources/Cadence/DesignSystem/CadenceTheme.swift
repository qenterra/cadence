import AppKit
import QenTerraDesignTokens
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
    static let qdsVersion = QDS.version
    static let primaryAccent = adaptive(QDS.Color.actionPrimary)
    static let contentBackground = adaptive(QDS.Color.surfaceContent)
    static let secondarySurface = adaptive(QDS.Color.surfaceSecondary)
    static let opaqueSurface = adaptive(QDS.Color.surfaceRaised)
    static let separator = adaptive(QDS.Color.borderDefault)
    static let strongSeparator = adaptive(QDS.Color.borderStrong)
    static let subduedFill = adaptive(QDS.Color.fillDisabled)
    static let selectionFill = adaptive(QDS.Color.fillSelected)
    static let increasedContrastSelectionFill = adaptive(
        QDS.Color.fillSelectedStrong
    )
    static let hoverFill = adaptive(QDS.Color.fillHover)
    static let informativeAccent = adaptive(QDS.Color.stateInformative)

    static let radiusNone = QDS.Radius.none
    static let radiusControl = QDS.Radius.control
    static let radiusGroup = QDS.Radius.group
    static let radiusPanel = QDS.Radius.panel
    static let radiusHero = QDS.Radius.hero
    static let radiusFloating = QDS.Radius.floating

    static let motionPress = QDS.MotionSeconds.press
    static let motionHover = QDS.MotionSeconds.hover
    static let motionPresent = QDS.MotionSeconds.present
    static let motionReplace = QDS.MotionSeconds.replace
    static let motionDismiss = QDS.MotionSeconds.dismiss
    static let motionSpatialLong = QDS.MotionSeconds.spatialLong

    // Product motion: Cadence Mode has no second consumer, so it stays named
    // here rather than inflating the cross-product QDS motion scale.
    static let motionCadenceModeEnter = 0.5
    static let motionCadenceModeExit = 0.55

    private static func adaptive(_ token: QDSColorValue) -> Color {
        let light = NSColor(Color(qds: token, appearance: .light))
        let dark = NSColor(Color(qds: token, appearance: .dark))
        return Color(
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
