import AppKit
import QenTerraDesignTokens
import SwiftUI

typealias CadenceColorValue = DesignColorValue

enum CadenceActionSemanticColor: Equatable, Sendable {
    case systemBlue
    case systemRed
}

enum CadenceActionTone: Equatable, Sendable {
    case confirmation
    case destructive

    var semanticColor: CadenceActionSemanticColor {
        switch self {
        case .confirmation: .systemBlue
        case .destructive: .systemRed
        }
    }
}

extension View {
    @ViewBuilder
    func cadenceActionTint(_ tone: CadenceActionTone) -> some View {
        switch tone.semanticColor {
        case .systemBlue:
            tint(.blue)
        case .systemRed:
            tint(.red)
        }
    }
}

enum CadenceAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
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
    static let actionPrimary = GeneratedTokens.Color.actionPrimary
    static let surfaceContent = GeneratedTokens.Color.surfaceContent
    static let surfaceSecondary = GeneratedTokens.Color.surfaceSecondary
    static let surfaceRaised = GeneratedTokens.Color.surfaceRaised
    static let borderDefault = GeneratedTokens.Color.borderDefault
    static let borderStrong = GeneratedTokens.Color.borderStrong
    static let fillDisabled = GeneratedTokens.Color.fillDisabled
    static let fillHover = GeneratedTokens.Color.fillHover
    static let fillSelected = GeneratedTokens.Color.fillSelected
    static let textPrimary = GeneratedTokens.Color.textPrimary
    static let textSecondary = GeneratedTokens.Color.textSecondary

    static let primaryAccent = adaptive(actionPrimary)
    static let contentBackground = adaptive(surfaceContent)
    static let secondarySurface = adaptive(surfaceSecondary)
    static let opaqueSurface = adaptive(surfaceRaised)
    static let separator = adaptive(borderDefault)
    static let strongSeparator = adaptive(borderStrong)
    static let subduedFill = adaptive(fillDisabled)
    static let selectionFill = adaptive(fillSelected)
    static let hoverFill = adaptive(fillHover)
    static let playerMetadata = adaptive(textSecondary)

    static let radiusNone = GeneratedTokens.Radius.none
    static let radiusControl = GeneratedTokens.Radius.control
    static let radiusGroup = GeneratedTokens.Radius.group
    static let radiusPanel = GeneratedTokens.Radius.panel
    static let radiusHero = GeneratedTokens.Radius.hero

    static let motionPress = GeneratedTokens.Motion.feedbackPress.seconds
    static let motionHover = GeneratedTokens.Motion.feedbackHover.seconds
    static let motionPresent = GeneratedTokens.Motion.floatingPresent.seconds
    static let motionReplace = GeneratedTokens.Motion.stateReplace.seconds
    static let motionDismiss = GeneratedTokens.Motion.floatingDismiss.seconds
    static let motionSpatialLong = GeneratedTokens.Motion.navigationSpatial.seconds

    // Product motion: Cadence Mode has no second consumer, so it stays named
    // here rather than inflating the shared feedback motion scale.
    static let motionCadenceModeEnter = 0.5
    private static func adaptive(_ token: CadenceColorValue) -> Color {
        Color(designToken: token)
    }
}
