import Foundation

extension RhythmAccentPalette {
    var backgroundColors: [RhythmPulseColor] {
        let darkenedColors = colors.map { color in
            RhythmPulseColor(
                red: color.red * 0.5,
                green: color.green * 0.5,
                blue: color.blue * 0.5
            )
        }
        guard let first = darkenedColors.first else {
            return []
        }
        if darkenedColors.count == 1 {
            return [
                first.scaled(by: 0.48),
                first.scaled(by: 1.18),
                first,
            ]
        }
        if darkenedColors.count == 2 {
            return [
                darkenedColors[0],
                darkenedColors[1],
                first.scaled(by: 0.5),
            ]
        }
        return darkenedColors
    }
}

private extension RhythmPulseColor {
    func scaled(by amount: Double) -> RhythmPulseColor {
        RhythmPulseColor(
            red: red * amount,
            green: green * amount,
            blue: blue * amount
        )
    }
}

struct CadenceModeBackgroundAppearance: Equatable, Sendable {
    let isAnimated: Bool
    let blurRadius: Double
    let animationDuration: TimeInterval
    let maximumAnimationFramesPerSecond: Int
    let gradientRasterizationScale: Double
    let animatedLayerCount: Int
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
            blurRadius: 0,
            animationDuration: 16,
            maximumAnimationFramesPerSecond: 120,
            gradientRasterizationScale: 0.33,
            animatedLayerCount: 2,
            baseOpacity: reduceTransparency ? 1 : 0.9,
            fieldOpacity: reduceTransparency ? 0.7 : 0.76,
            scrimOpacity: increasedContrast ? 0.54 : 0.36
        )
    }
}
