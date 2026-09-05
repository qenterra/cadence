import AppKit
import SwiftUI

struct CadenceColorValue: Equatable, Sendable {
    let light: String
    let dark: String
}

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
    static let actionPrimary = CadenceColorValue(
        light: "#1A1A1C",
        dark: "#FFFFFF"
    )
    static let surfaceContent = CadenceColorValue(
        light: "#F4F4F6",
        dark: "#171719"
    )
    static let surfaceSecondary = CadenceColorValue(
        light: "#E8E8EC",
        dark: "#202023"
    )
    static let surfaceRaised = CadenceColorValue(
        light: "#E0E0E6",
        dark: "#27272B"
    )
    static let borderDefault = CadenceColorValue(
        light: "rgba(15, 15, 17, 0.12)",
        dark: "rgba(255, 255, 255, 0.13)"
    )
    static let borderStrong = CadenceColorValue(
        light: "rgba(15, 15, 17, 0.22)",
        dark: "rgba(255, 255, 255, 0.24)"
    )
    static let fillDisabled = CadenceColorValue(
        light: "rgba(15, 15, 17, 0.04)",
        dark: "rgba(255, 255, 255, 0.04)"
    )
    static let fillHover = CadenceColorValue(
        light: "rgba(15, 15, 17, 0.045)",
        dark: "rgba(255, 255, 255, 0.045)"
    )
    static let fillSelected = CadenceColorValue(
        light: "rgba(15, 15, 17, 0.075)",
        dark: "rgba(255, 255, 255, 0.085)"
    )
    static let fillSelectedStrong = CadenceColorValue(
        light: "rgba(15, 15, 17, 0.14)",
        dark: "rgba(255, 255, 255, 0.14)"
    )
    static let textPrimary = CadenceColorValue(
        light: "#1A1A1C",
        dark: "#FFFFFF"
    )
    static let textSecondary = CadenceColorValue(
        light: "#56565E",
        dark: "#B9B9C0"
    )

    static let primaryAccent = adaptive(actionPrimary)
    static let contentBackground = adaptive(surfaceContent)
    static let secondarySurface = adaptive(surfaceSecondary)
    static let opaqueSurface = adaptive(surfaceRaised)
    static let separator = adaptive(borderDefault)
    static let strongSeparator = adaptive(borderStrong)
    static let subduedFill = adaptive(fillDisabled)
    static let selectionFill = adaptive(fillSelected)
    static let selectionStrongFill = adaptive(fillSelectedStrong)
    static let hoverFill = adaptive(fillHover)
    static let playerMetadata = adaptive(textSecondary)
    static let nativePrimaryAccent = adaptiveNSColor(actionPrimary)
    static let nativeSelectionFill = adaptiveNSColor(fillSelected)
    static let nativeHoverFill = adaptiveNSColor(fillHover)

    static let radiusNone = 0.0
    static let radiusControl = 6.0
    static let radiusGroup = 10.0
    static let radiusPanel = 14.0
    static let radiusHero = 18.0

    static let motionPress = 0.08
    static let motionHover = 0.1
    static let motionPresent = 0.14
    static let motionReplace = 0.15
    static let motionDismiss = 0.16
    static let motionSpatialLong = 0.24

    static func playerControl(
        _ state: PlayerControlVisualState
    ) -> Color {
        adaptive(state.token)
    }

    // Product motion: Cadence Mode has no second consumer, so it stays named
    // here rather than inflating the shared feedback motion scale.
    static let motionCadenceModeEnter = 0.5
    private static func adaptive(_ token: CadenceColorValue) -> Color {
        Color(nsColor: adaptiveNSColor(token))
    }

    private static func adaptiveNSColor(
        _ token: CadenceColorValue
    ) -> NSColor {
        let light = nsColor(token.light)
        let dark = nsColor(token.dark)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(
                from: [.darkAqua, .aqua]
            ) == .darkAqua ? dark : light
        }
    }

    private static func nsColor(
        _ source: String
    ) -> NSColor {
        if source.hasPrefix("#"),
           source.count == 7,
           let value = UInt64(source.dropFirst(), radix: 16) {
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }
        let values = source
            .replacingOccurrences(of: "rgba(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 4 else {
            return .clear
        }
        return NSColor(
            srgbRed: values[0] / 255,
            green: values[1] / 255,
            blue: values[2] / 255,
            alpha: values[3]
        )
    }
}
