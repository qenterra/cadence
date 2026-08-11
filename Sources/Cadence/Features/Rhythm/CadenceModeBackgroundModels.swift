import Foundation

extension RhythmAccentPalette {
    var backgroundColors: [RhythmPulseColor] {
        colors.map { color in
            RhythmPulseColor(
                red: color.red * 0.52,
                green: color.green * 0.52,
                blue: color.blue * 0.52
            )
        }
    }
}

struct CadenceModeBackgroundAppearance: Equatable, Sendable {
    let isAnimated: Bool
    let blurRadius: Double
    let baseOpacity: Double
    let fieldOpacity: Double
    let scrimOpacity: Double

    static func resolve(
        reduceMotion: Bool,
        reduceTransparency: Bool,
        increasedContrast: Bool
    ) -> CadenceModeBackgroundAppearance {
        CadenceModeBackgroundAppearance(
            isAnimated: !reduceMotion,
            blurRadius: 110,
            baseOpacity: reduceTransparency ? 1 : 0.84,
            fieldOpacity: reduceTransparency ? 0.72 : 0.62,
            scrimOpacity: increasedContrast ? 0.58 : 0.42
        )
    }
}
